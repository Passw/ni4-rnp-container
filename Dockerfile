# syntax=docker/dockerfile:1

# Container image for RNP, the Ribose OpenPGP implementation.
# https://github.com/rnpgp/rnp

ARG BASE_IMAGE=ubuntu:24.04

# Crypto backend passed to RNP's CMake: openssl, botan or botan3. The last
# requires Botan 3, while botan accepts either major version. Declared here,
# before the first stage, so it can select the Botan stage below.
ARG CRYPTO_BACKEND=openssl

# Botan release to build from source, as a tag of randombit/botan. Ubuntu
# only packages Botan 2, so Botan 3 is compiled here.
ARG BOTAN_VERSION=3.13.0

# ---------------------------------------------------------------------------
# base: dependencies shared by every stage
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libbz2-1.0 \
        libjson-c5 \
        libssl3t64 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Botan, staged under /botan-out so later stages can copy it as a unit.
#
# One stage per value of CRYPTO_BACKEND. The openssl variant stages nothing,
# which keeps the copy below unconditional while still building no Botan at
# all when it is not wanted.
# ---------------------------------------------------------------------------
FROM base AS botan-source

ARG BOTAN_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        libbz2-dev \
        python3 \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${BOTAN_VERSION}" \
        https://github.com/randombit/botan.git /usr/local/src/botan

WORKDIR /usr/local/src/botan

# Only the shared library is needed: no static archive, CLI or handbook.
RUN ./configure.py \
        --prefix=/usr/local \
        --build-targets=shared \
        --with-bzip2 \
        --with-zlib \
        --without-documentation \
    && make -j"$(nproc)" \
    && make install DESTDIR=/botan-out \
    && rm -rf /botan-out/usr/local/share

FROM base AS botan-openssl
RUN mkdir -p /botan-out/usr/local/lib /botan-out/usr/local/include

FROM botan-source AS botan-botan
FROM botan-source AS botan-botan3

# Resolves to whichever of the three stages above matches CRYPTO_BACKEND.
FROM botan-${CRYPTO_BACKEND} AS botan

# ---------------------------------------------------------------------------
# builder: toolchain plus an RNP build from source
# ---------------------------------------------------------------------------
FROM base AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        libbz2-dev \
        libjson-c-dev \
        libssl-dev \
        ninja-build \
        pkg-config \
        python3 \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Empty for the openssl backend.
COPY --from=botan /botan-out/ /
RUN ldconfig

# Git ref of rnpgp/rnp to build: a tag, branch or commit.
ARG RNP_VERSION=main
ARG CRYPTO_BACKEND
ARG BUILD_TYPE=Release

WORKDIR /usr/local/src

RUN git clone --recursive --depth 1 --branch "${RNP_VERSION}" \
        https://github.com/rnpgp/rnp.git rnp

WORKDIR /usr/local/src/rnp

RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCRYPTO_BACKEND="${CRYPTO_BACKEND}" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
    && cmake --build build \
    && cmake --install build --prefix /out/usr/local \
    && cmake --install build

# ---------------------------------------------------------------------------
# dev: full toolchain, source tree mounted from the host
# ---------------------------------------------------------------------------
FROM builder AS dev

RUN apt-get update && apt-get install -y --no-install-recommends \
        gdb \
        gnupg \
        less \
        python3-venv \
        sudo \
        valgrind \
        vim \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
CMD ["/bin/bash"]

# ---------------------------------------------------------------------------
# runtime: rnp and rnpkeys only
# ---------------------------------------------------------------------------
FROM base AS runtime

# The Botan shared library, or nothing for the openssl backend.
COPY --from=botan /botan-out/usr/local/lib/ /usr/local/lib/
COPY --from=builder /out/usr/local/ /usr/local/
RUN ldconfig

# Unprivileged user with a writable home for the OpenPGP keyring.
# The keyring directory must exist and be owned by rnp in the image: Docker
# copies its ownership onto a named volume mounted there, and a volume over a
# missing directory would be created root-owned and unwritable.
RUN useradd --create-home --shell /bin/bash rnp \
    && install -d -o rnp -g rnp -m 700 /home/rnp/.rnp
USER rnp
WORKDIR /home/rnp

ENTRYPOINT ["rnp"]
CMD ["--version"]
