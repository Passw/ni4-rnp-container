# rnp-container

Container images for [RNP](https://github.com/rnpgp/rnp), the Ribose OpenPGP
implementation.

The [Dockerfile](Dockerfile) builds RNP from source against Ubuntu 24.04 and
produces three targets:

| Target    | Contents                                                     | Size    |
|-----------|--------------------------------------------------------------|---------|
| `builder` | Toolchain plus a full RNP build tree                         | ~1 GB   |
| `dev`     | `builder` plus gdb, valgrind, gnupg and a shell              | ~1.1 GB |
| `runtime` | Slim image with `rnp`, `rnpkeys` and the shared library only | ~157 MB |

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
| `botan3`  | Botan, with RNP requiring version 3.                |

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

## Volumes

The `rnp` and `rnpkeys` services share a `keyring` volume mounted at
`/home/rnp/.rnp`, so keys generated in one run are still there in the next.
Because `dev` runs as root, it gets a separate `dev-keyring` volume rather than
writing root-owned files into the first one. Remove both with
`docker compose down --volumes`.
