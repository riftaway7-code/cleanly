#!/bin/bash

set -euo pipefail

install_prefix="${INSTALL_PREFIX:-/usr/local}"
binary="$install_prefix/bin/cleanly"
state_dir="${CLEANLY_HOME:-$HOME/.cleanly}"

echo "Uninstall: Removing $binary."
sudo rm -f "$binary"

read -r -p "Archive settings and history from $state_dir? [y/N] " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    if [[ -d "$state_dir" ]]; then
        archive_path="$state_dir.uninstalled-$(date +%Y%m%d-%H%M%S)"
        mv "$state_dir" "$archive_path"
        echo "Archive: Settings and history were moved to $archive_path."
    else
        echo "Archive: No settings directory was found."
    fi
fi

echo "Result: cleanly uninstalled."
