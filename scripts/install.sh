#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
install_prefix="${INSTALL_PREFIX:-/usr/local}"
install_dir="$install_prefix/bin"
binary="$project_dir/.build/release/cleanly"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: cleanly supports macOS only."
    exit 1
fi

echo "Build: Compiling cleanly in release mode."
swift build --package-path "$project_dir" --configuration release

echo "Install: Copying cleanly to $install_dir."
sudo mkdir -p "$install_dir"
sudo install -m 0755 "$binary" "$install_dir/cleanly"

echo "Result: cleanly installed. Run 'cleanly help' to get started."
