# syntax=docker/dockerfile:1

# Container image for RNP, the Ribose OpenPGP implementation.
# https://github.com/rnpgp/rnp

ARG BASE_IMAGE=ubuntu:24.04

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

# Git ref of rnpgp/rnp to build: a tag, branch or commit.
ARG RNP_VERSION=main
# openssl or botan
ARG CRYPTO_BACKEND=openssl
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
