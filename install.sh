#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
install_dir=${INSTALL_DIR:-"$HOME/.local/bin"}

mkdir -p "$install_dir"
install -m 0755 "$source_dir/agent" "$install_dir/agent"

printf 'Installed launcher: %s/agent\n' "$install_dir"
if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  printf 'Add %s to PATH to use the agent command.\n' "$install_dir"
fi
printf 'Build images with: task build\n'
