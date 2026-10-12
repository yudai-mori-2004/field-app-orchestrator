#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
appium_home="$repo_root/.appium"
xcuitest_version="12.17.2"

cd "$repo_root"

if command -v mise >/dev/null 2>&1; then
  mise install
  command_prefix=(mise exec --)
else
  command_prefix=()
fi

node_version="$("${command_prefix[@]}" node --version)"
if [[ "$node_version" != "v22.23.3" ]]; then
  echo "Node 22.23.3 is required; found $node_version." >&2
  echo "Install mise or activate the version declared in .mise.toml." >&2
  exit 69
fi

"${command_prefix[@]}" npm ci
mkdir -p "$appium_home"

installed_drivers="$(APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium driver list --installed)"
if [[ "$installed_drivers" != *"xcuitest@$xcuitest_version"* ]]; then
  if [[ "$installed_drivers" == *"xcuitest@"* ]]; then
    APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium driver uninstall xcuitest
  fi
  APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium driver install "appium-xcuitest-driver@$xcuitest_version" --source=npm
fi

APPIUM_HOME="$appium_home" "${command_prefix[@]}" npx appium driver list --installed
