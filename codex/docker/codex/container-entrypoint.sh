#!/bin/sh
set -eu

persist_directory() {
    image_path=$1
    persistent_path=$2

    if [ -L "$image_path" ] && [ "$(readlink "$image_path")" = "$persistent_path" ]; then
        return
    fi

    if [ ! -e "$persistent_path" ] && [ ! -L "$persistent_path" ]; then
        mkdir -p "$(dirname "$persistent_path")"
        if [ -d "$image_path" ]; then
            cp -a "$image_path" "$persistent_path"
        else
            mkdir "$persistent_path"
        fi
    elif [ ! -d "$persistent_path" ]; then
        printf '%s exists but is not a directory\n' "$persistent_path" >&2
        exit 1
    fi

    rm -rf "$image_path"
    ln -s "$persistent_path" "$image_path"
}

cd /
persist_directory /root/Documents /persist/root/Documents
persist_directory /root/.codex /persist/root/.codex
persist_directory /workspace /persist/workspace
cd /workspace

exec codex -c 'sandbox_mode="danger-full-access"' app-server "$@"