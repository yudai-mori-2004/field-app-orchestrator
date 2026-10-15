#!/bin/bash
# Lists the URLs each iPhone's back-tap shortcuts send, so that they are
# copied from a file sent to the iPhone instead of typed on it. Run it on the
# Mac that runs field-app: the URLs name this Mac's local host name.
#
# usage: tools/shortcut_urls.sh <env file>...

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: tools/shortcut_urls.sh <env file>..." >&2
  exit 64
fi

host="$(scutil --get LocalHostName).local"
for env_file in "$@"; do
  [[ -f "$env_file" ]] || { echo "No such env file: $env_file" >&2; exit 66; }
  read -r label port token < <(
    set -a; . "$env_file"
    printf '%s %s %s\n' "${FAO_DEVICE_LABEL:-}" "${FAO_CONTROL_PORT:-}" "${FAO_CONTROL_TOKEN:-}"
  )
  if [[ -z "$label" || -z "$port" || -z "$token" ]]; then
    echo "$env_file does not set FAO_DEVICE_LABEL, FAO_CONTROL_PORT, and FAO_CONTROL_TOKEN." >&2
    exit 65
  fi
  printf '開始 %s\nhttp://%s:%s/start?token=%s\n\n' "$label" "$host" "$port" "$token"
  printf '終了 %s\nhttp://%s:%s/pause?token=%s\n\n' "$label" "$host" "$port" "$token"
done
