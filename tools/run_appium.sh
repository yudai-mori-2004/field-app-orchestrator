#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
appium_home="$repo_root/.appium"
mode="${1:-}"

cd "$repo_root"

if command -v mise >/dev/null 2>&1; then
  command_prefix=(mise exec --)
else
  command_prefix=()
fi

node_version="$("${command_prefix[@]}" node --version)"
if [[ "$node_version" != "v22.23.3" ]]; then
  echo "Node 22.23.3 is required; found $node_version." >&2
  echo "Run npm run setup:appium with mise installed, or activate the version in .mise.toml." >&2
  exit 69
fi

case "$mode" in
  server)
    APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium \
      --base-path / \
      --log-timestamp \
      --log-no-colors
    ;;
  doctor)
    APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium driver doctor xcuitest
    ;;
  *)
    echo "Usage: $0 {server|doctor}" >&2
    exit 64
    ;;
esac
