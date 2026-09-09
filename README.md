# rnp-container

Container images for [RNP](https://github.com/rnpgp/rnp), the Ribose OpenPGP
implementation.

The [Dockerfile](Dockerfile) builds RNP from source against Ubuntu 24.04 and
produces three targets:

| Target    | Contents                                                     | Size    |
|-----------|--------------------------------------------------------------|---------|
| `builder` | Toolchain plus a full RNP build tree                         | ~1 GB   |
| `dev`     | `builder` plus gdb, valgrind, gnupg and a shell              | ~1.1 GB |
| `runtime` | Slim image with `rnp`, `rnpkeys` and the shared library only | ~174 MB |

Compose defaults to the Botan 3 backend, which compiles Botan from source and
makes the first build slow. For a fast build against system OpenSSL, put
`CRYPTO_BACKEND=openssl` in `.env`.

## Usage

Build and print the version:

```sh
docker compose run --rm rnp --version
```

List the keys in the persistent keyring volume:

```sh
docker compose run --rm rnpkeys --list-keys
```

Files in `./data` are visible to the container as `/data`, which is also the
working directory, so paths on the command line are relative to it:

```sh
mkdir -p data && echo hello > data/message.txt
docker compose run --rm rnp --clearsign message.txt
```

Open a shell in the build environment:

```sh
docker compose run --rm dev
```

The `dev` service has no entrypoint, so a one-off command needs the shell
spelled out:

```sh
docker compose run --rm dev bash -c 'cmake --version'
```

The `dev` service mounts `./src` as `/work`. Clone a working tree there to
build and test it inside the container.

## Configuration

Copy [.env.example](.env.example) to `.env` to pick the RNP revision, the
crypto backend and the CMake build type. The same values can be passed
directly to a plain `docker build`:

```sh
docker build --target runtime --build-arg RNP_VERSION=v0.17.1 -t rnp:v0.17.1 .
```

### Crypto backend

`CRYPTO_BACKEND` takes the three values RNP itself accepts:

| Value     | Meaning                                            |
|-----------|----------------------------------------------------|
| `openssl` | System OpenSSL. Nothing extra is compiled.          |
| `botan`   | Botan, with RNP accepting either major version.     |
| `botan3`  | Botan, with RNP requiring version 3. Compose default. |

The backend is part of the image tag Compose builds, as in `rnp:main-botan3`
and `rnp:main-openssl`, so switching backends does not overwrite the image you
built with the other one.

Ubuntu packages only Botan 2, so both Botan values compile Botan from source
at the tag named by `BOTAN_VERSION`:

```sh
docker build --target runtime \
  --build-arg CRYPTO_BACKEND=botan3 \
  --build-arg BOTAN_VERSION=3.13.0 \
  -t rnp:botan3 .
```

Any tag of [randombit/botan](https://github.com/randombit/botan) works. Note
that there is no 3.0.7: the 3.0 series ends at 3.0.0 and continues at 3.1.0,
so the usable 3.x tags run 3.0.0, 3.1.0, 3.1.1, 3.2.0 and onward to 3.13.0.

Only the shared library is built, without the command line tool, the static
archive or the handbook. It still adds several minutes to a cold build, and
the layer is cached afterwards, keyed on `BOTAN_VERSION`.

The backend is selected by resolving a stage named `botan-$CRYPTO_BACKEND`,
which Docker does before running anything, so a misspelled value surfaces as a
registry error rather than a validation message:

```
ERROR: pull access denied, repository does not exist: botan-bogus
```

That means `CRYPTO_BACKEND` was not one of the three values above.

## Walkthrough

Pin a Botan release, generate a key inside the image, then sign and verify a
file. The commands below were run as written against Botan 3.12.0.

Build the image:

```sh
docker build --target runtime \
  --build-arg CRYPTO_BACKEND=botan3 \
  --build-arg BOTAN_VERSION=3.12.0 \
  -t rnp:botan-3.12.0 .

docker run --rm rnp:botan-3.12.0 --version
```

```
rnp 0.18.1+git20260909.470695b
Ribose Inc. <rnpgp@ribose.com>
Backend: Botan
Backend version: 3.12.0
```

Create a volume for the keyring and a file to sign:

```sh
docker volume create rnp-demo
mkdir -p data && echo "the quick brown fox" > data/message.txt
```

Generate a key. The passphrase is on the command line only to keep the block
copy-pasteable. Drop `--password` and you are prompted for it instead, which
is what you want outside a demo:

```sh
docker run --rm -v rnp-demo:/home/rnp/.rnp \
  --entrypoint rnpkeys rnp:botan-3.12.0 \
  --generate-key --userid "Alice <alice@example.com>" \
  --password "demo passphrase"
```

```
sec   3072/RSA c479a0d55d4310be 2026-09-09 [SC] [EXPIRES 2028-09-08]
      7cd57be036fd8705c41ee5bdc479a0d55d4310be
uid           Alice <alice@example.com>
```

Sign the file. The image entrypoint is `rnp`, so arguments go straight to it:

```sh
docker run --rm -v rnp-demo:/home/rnp/.rnp -v "$PWD/data:/data" -w /data \
  rnp:botan-3.12.0 --clearsign message.txt --password "demo passphrase"
```

This writes `data/message.txt.asc` on the host, owned by your account.

Verify it:

```sh
docker run --rm -v rnp-demo:/home/rnp/.rnp -v "$PWD/data:/data" -w /data \
  rnp:botan-3.12.0 --verify message.txt.asc
```

```
Good signature made Wed Sep  9 07:39:13 2026
using RSA key c479a0d55d4310be
uid           Alice <alice@example.com>
Signature(s) verified successfully
```

Note that `rnp` writes these messages to standard error, so redirect with
`2>&1` if you are piping them anywhere.

Drop the demo keyring when you are done:

```sh
docker volume rm rnp-demo
```

### The same run through Compose

Compose already declares the keyring volume, the `./data` mount and the
working directory, so the commands shrink:

```sh
printf 'CRYPTO_BACKEND=botan3\nBOTAN_VERSION=3.12.0\n' > .env
docker compose build rnp

mkdir -p data && echo "the quick brown fox" > data/message.txt

docker compose run --rm rnpkeys --generate-key --userid "Alice <alice@example.com>"
docker compose run --rm rnp --clearsign message.txt
docker compose run --rm rnp --verify message.txt.asc
```

`docker compose run` attaches a terminal, so the passphrase prompt works and
`--password` can be left out. Remove the keyring afterwards with
`docker compose down --volumes`.

## Continuous integration

[.github/workflows/ci.yml](.github/workflows/ci.yml) builds and exercises every
backend on each push and pull request, and again weekly, since RNP `main` and
the Botan releases move on their own schedule.

| Job          | What it covers                                                  |
|--------------|-----------------------------------------------------------------|
| `runtime`    | A matrix over the backends, each one smoke tested                |
| `compose`    | The compose file parses, and the backend reaches the image tag    |
| `dev-image`  | The dev target builds and carries its toolchain and source tree   |
| `lint`       | shellcheck, plus hadolint over the Dockerfile                     |

The `runtime` matrix covers OpenSSL, `botan` at 3.13.0, and `botan3` at 3.13.0,
3.12.0 and 3.0.0. The last is the oldest Botan 3 release and marks the floor of
what this image supports.

Each matrix entry runs [scripts/smoke-test.sh](scripts/smoke-test.sh), which
checks the backend RNP reports, generates a key, signs and verifies a file
through a bind mount, and confirms that a tampered signature is rejected. Run
it against any image you have built:

```sh
scripts/smoke-test.sh rnp:main-botan3 Botan 3.13.0
```

The backend name is required and the version optional. Both are compared
against what `rnp --version` prints, so a build that silently picked the wrong
backend fails rather than passing quietly.

Builds use the GitHub Actions cache keyed on the backend and Botan version, so
only the first run of each combination pays for compiling Botan. The matrix
runs on x86-64 runners only; the images also build on arm64, which is where
they were developed.

## Volumes

The `rnp` and `rnpkeys` services share a `keyring` volume mounted at
`/home/rnp/.rnp`, so keys generated in one run are still there in the next.
Because `dev` runs as root, it gets a separate `dev-keyring` volume rather than
writing root-owned files into the first one. Remove both with
`docker compose down --volumes`.

## License

BSD 2-Clause, matching [RNP itself](https://github.com/rnpgp/rnp). See
[LICENSE.md](LICENSE.md).

This repository holds only the container definitions and the scripts around
them. RNP and Botan are fetched from their own upstream sources at build time
and are covered by their own licenses.
