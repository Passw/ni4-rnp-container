# rnp-container

Container images for [RNP](https://github.com/rnpgp/rnp), the Ribose OpenPGP
implementation.

The [Dockerfile](Dockerfile) builds RNP from source against Ubuntu 24.04 and
produces three targets:

| Target    | Contents                                                    |
|-----------|-------------------------------------------------------------|
| `builder` | Toolchain plus a full RNP build tree                         |
| `dev`     | `builder` plus gdb, valgrind, gnupg and a shell              |
| `runtime` | Slim image with `rnp`, `rnpkeys` and the shared library only |

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

The `dev` service mounts `./src` as `/work`. Clone a working tree there to
build and test it inside the container.

## Configuration

Copy [.env.example](.env.example) to `.env` to pick the RNP revision, the
crypto backend and the CMake build type. The same values can be passed
directly to a plain `docker build`:

```sh
docker build --target runtime \
  --build-arg RNP_VERSION=v0.17.1 \
  --build-arg CRYPTO_BACKEND=botan \
  -t rnp:v0.17.1 .
```

Note that `CRYPTO_BACKEND=botan` needs Botan development packages added to the
`builder` stage; only the OpenSSL backend builds out of the box.

## Volumes

The keyring lives in a named volume mounted at `~/.rnp`, so keys generated in
one run are still there in the next. Remove it with
`docker compose down --volumes`.
