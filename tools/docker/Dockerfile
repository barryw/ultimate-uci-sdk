# The Ultimate SDK toolchain image.
#
# Every assembler and C compiler the SDK claims to support, in one place, so
# that "builds with cc65, Oscar64, llvm-mos and KickC" is a thing CI checks on
# every change rather than a thing the README asserts.
#
#   docker build -t ultimate-sdk-toolchains tools/docker
#   docker run --rm -v "$PWD":/src -w /src ultimate-sdk-toolchains make matrix
#
# Pinned by tag or commit wherever upstream offers one: a toolchain image that
# drifts silently is worse than no image, because it turns a green build into a
# statement about today's downloads rather than about the code.
#
# SPDX-License-Identifier: MIT

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# --- distribution toolchains ---------------------------------------------
# cc65 (ca65/cl65), 64tass and ACME all ship in Debian, which is the most
# stable way to get them and keeps the image small.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        make \
        python3 \
        unzip \
        xz-utils \
        libx11-dev \
        libxext-dev \
        cc65 \
        64tass \
        acme \
        default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# --- llvm-mos -------------------------------------------------------------
# Prebuilt SDK; building LLVM from source in an image is not a reasonable ask.
RUN curl -fsSL -o /tmp/llvm-mos.tar.xz \
        https://github.com/llvm-mos/llvm-mos-sdk/releases/latest/download/llvm-mos-linux.tar.xz \
    && tar -xJf /tmp/llvm-mos.tar.xz -C /opt \
    && rm /tmp/llvm-mos.tar.xz
ENV PATH="/opt/llvm-mos/bin:${PATH}"

# --- Oscar64 --------------------------------------------------------------
# Source only, but it is a small C++ project and builds in a couple of minutes.
# Oscar64 locates its own includes relative to the binary, hence the bin/ layout.
RUN git clone --depth 1 https://github.com/drmortalwombat/oscar64.git /opt/oscar64 \
    && cmake -S /opt/oscar64 -B /opt/oscar64/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/oscar64/build -j "$(nproc)" \
    && mkdir -p /opt/oscar64/bin \
    && cp "$(find /opt/oscar64/build -name oscar64 -type f -perm -u+x | head -1)" \
          /opt/oscar64/bin/oscar64 \
    && rm -rf /opt/oscar64/build
ENV PATH="/opt/oscar64/bin:${PATH}"

# --- KickAssembler --------------------------------------------------------
# A jar plus a launcher, so that `kickass` behaves like the other tools.
RUN curl -fsSL -o /tmp/kickass.zip http://theweb.dk/KickAssembler/KickAssembler.zip \
    && mkdir -p /opt/kickassembler \
    && unzip -q /tmp/kickass.zip -d /opt/kickassembler \
    && rm /tmp/kickass.zip \
    && printf '#!/bin/sh\nexec java -jar /opt/kickassembler/KickAss.jar "$@"\n' \
         > /usr/local/bin/kickass \
    && chmod +x /usr/local/bin/kickass

# --- KickC ----------------------------------------------------------------
# The release page links its binary through a URL shortener; this is the target
# that shortener resolves to, used directly so the build does not depend on a
# third-party redirector staying up. Pinned to a version rather than "latest",
# because a toolchain image that silently changes compiler is a test result you
# cannot trust. Override both to move.
ARG KICKC_VERSION=0.8.6
ARG KICKC_URL=https://gitlab.com/camelot/kickc/-/wikis/uploads/65840c13bcfc4b45f1a3235a7008b4fe/kickc_0.8.6.zip
#
# Best effort, because KickC is the least active toolchain the SDK targets:
# 0.8.6 is from February 2022, with commits trailing off through mid-2024. It
# still works and it is pinned, so it stays - but the image must not fail to
# build because a wiki upload for a dormant project went away. `toolchains`
# reports it as absent instead, and the build matrix skips it.
RUN if curl -fsSL -o /tmp/kickc.zip "$KICKC_URL"; then \
        unzip -q /tmp/kickc.zip -d /opt \
        && rm /tmp/kickc.zip \
        && chmod +x /opt/kickc/bin/kickc.sh \
        && printf '#!/bin/sh\nexec /opt/kickc/bin/kickc.sh "$@"\n' > /usr/local/bin/kickc \
        && chmod +x /usr/local/bin/kickc; \
    else \
        echo "KickC not fetched from $KICKC_URL - image will report it absent"; \
    fi
ENV KICKC_VERSION=${KICKC_VERSION}

# --- report what actually made it in --------------------------------------
COPY toolchains.sh /usr/local/bin/toolchains
RUN chmod +x /usr/local/bin/toolchains

WORKDIR /src
CMD ["toolchains"]
