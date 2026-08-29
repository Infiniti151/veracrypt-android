# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Infiniti151

FROM registry.fedoraproject.org/fedora:44

ARG TERMUX_FUSE3_VERSION=3.16.2-1
ARG TERMUX_FUSE3_URL=https://packages.termux.dev/apt/termux-root/pool/stable/libf/libfuse3/libfuse3_${TERMUX_FUSE3_VERSION}_aarch64.deb

ARG TERMUX_PCSC_VERSION=2.5.1
ARG TERMUX_PCSC_URL=https://packages.termux.dev/apt/termux-main/pool/main/libp/libpcsclite/libpcsclite_${TERMUX_PCSC_VERSION}_aarch64.deb

# Install build dependencies, C/C++ toolchain, and packaging utilities
RUN dnf update -y && \
    dnf install -y \
        make \
        gcc \
        gcc-c++ \
        cmake \
        git \
        wget \
        unzip \
        tar \
        bzip2 \
        pkg-config \
        file \
        apt-utils \
        dpkg \
        dpkg-dev && \
    dnf clean all

# ---------------------------------------------------------------------------
# Termux development files
# ---------------------------------------------------------------------------

RUN mkdir -p /opt/termux-fuse3 && \
    wget -O /tmp/libfuse3.deb "$TERMUX_FUSE3_URL" && \
    dpkg-deb -x /tmp/libfuse3.deb /opt/termux-fuse3 && \
    rm -f /tmp/libfuse3.deb

RUN mkdir -p /opt/termux-pcsclite && \
    wget -O /tmp/libpcsclite.deb "$TERMUX_PCSC_URL" && \
    dpkg-deb -x /tmp/libpcsclite.deb /opt/termux-pcsclite && \
    rm -f /tmp/libpcsclite.deb

WORKDIR /workspace

RUN mkdir -p /workspace/output /workspace/cache