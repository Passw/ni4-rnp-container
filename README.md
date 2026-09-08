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

Only the OpenSSL backend builds out of the box. `CRYPTO_BACKEND=botan` also
needs Botan development packages added to the `builder` stage.

## Volumes

The `rnp` and `rnpkeys` services share a `keyring` volume mounted at
`/home/rnp/.rnp`, so keys generated in one run are still there in the next.
Because `dev` runs as root, it gets a separate `dev-keyring` volume rather than
writing root-owned files into the first one. Remove both with
`docker compose down --volumes`.
