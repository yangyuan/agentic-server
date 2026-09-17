#!/bin/sh
set -eu

ESSENTIAL_ONLY=false
if [ "$#" -eq 1 ] && [ "$1" = --essential ]; then
    ESSENTIAL_ONLY=true
elif [ "$#" -ne 0 ]; then
    printf 'Usage: sh "%s" [--essential]\n' "$0" >&2
    exit 2
fi

EFFECTIVE_UID="$(id -u)"

if [ "$EFFECTIVE_UID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    printf 'sudo is unavailable; run this script as root to bootstrap minimal Ubuntu.\n' >&2
    exit 1
fi

run_privileged() {
    if [ "$EFFECTIVE_UID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_packages() {
    run_privileged env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "$@"
}

run_privileged apt-get update

# Essential: prerequisites for app-server setup on minimal Ubuntu.
install_packages \
    build-essential \
    ca-certificates \
    curl \
    python3 \
    sudo \
    tar \
    xz-utils

run_privileged update-ca-certificates

# Experience: additional Ubuntu 24.04 tools, including essential packages above.
if [ "$ESSENTIAL_ONLY" = false ]; then
    # Development and file tools.
    set -- \
        file \
        fuse3 \
        git-lfs \
        inotify-tools \
        musl-tools \
        ripgrep \
        rsync \
        zstd

    # Libraries: libcurl for network transfers, NSPR for portable threading/I/O,
    # and NSS for cryptography/TLS.
    set -- "$@" \
        libcurl4t64 \
        libnspr4 \
        libnss3

    # Headless Java 17 runtime.
    set -- "$@" openjdk-17-jre-headless

    # Supervisor process manager.
    set -- "$@" supervisor

    # Fonts and graphics.
    set -- "$@" \
        fontconfig \
        imagemagick \
        inkscape \
        libfontconfig1 \
        libfreetype6 \
        libjxr-tools \
        liblcms2-2

    # PDF and optical character recognition.
    set -- "$@" \
        ghostscript \
        ocrmypdf \
        poppler-utils \
        tesseract-ocr

    # Document authoring and typesetting.
    set -- "$@" \
        latexmk \
        lmodern \
        pandoc \
        texlive-fonts-recommended \
        texlive-xetex

    # Audio and video.
    set -- "$@" ffmpeg

    install_packages "$@"
    run_privileged fc-cache -fv
fi

run_privileged rm -rf /var/lib/apt/lists/*