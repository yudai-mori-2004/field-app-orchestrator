#!/bin/bash
# Keeps field-app running for one iPhone as a launchd service. The service
# starts at login, is started again if it dies, and writes its events to a
# log.
#
# usage: tools/service.sh install <env file> <definition file>
#        tools/service.sh remove <env file>
#        tools/service.sh plist <env file> <definition file>
#
# The env file sets FAO_DEVICE_ID, FAO_DEVICE_LABEL, and the other variables
# field-app reads. `install` builds field-app and replaces a service already
# registered for the iPhone. Stopping a service pauses the recording first.
# `plist` only prints the service definition.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: tools/service.sh install <env file> <definition file>
       tools/service.sh remove <env file>
       tools/service.sh plist <env file> <definition file>
USAGE
  exit 64
}

absolute() {
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

xml() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"
}

[[ $# -ge 2 ]] || usage
verb="$1"
[[ -f "$2" ]] || { echo "No such env file: $2" >&2; exit 66; }
env_file="$(absolute "$2")"

label="$(set -a; . "$env_file"; printf '%s' "${FAO_DEVICE_LABEL:-}")"
if [[ ! "$label" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Set FAO_DEVICE_LABEL in the env file, using letters, digits, '.', '_' and '-'." >&2
  exit 65
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="$repo/mac/controller-core/.build/release/field-app"
service="dev.fieldapporchestrator.field-app.$label"
domain="gui/$(id -u)"
plist_file="$HOME/Library/LaunchAgents/$service.plist"
log_file="$HOME/Library/Logs/field-app/$label.log"

# AbandonProcessGroup leaves the xcodebuild that hosts WebDriverAgent running
# when field-app exits, so the next field-app uses it again. ExitTimeOut
# gives field-app time to pause the recording before launchd kills it.
plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$service</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>set -a; . "\$1"; set +a; exec "\$2" --definition "\$3"</string>
    <string>field-app</string>
    <string>$(xml "$env_file")</string>
    <string>$(xml "$binary")</string>
    <string>$(xml "$1")</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$(xml "$repo")</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>AbandonProcessGroup</key>
  <true/>
  <key>ExitTimeOut</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>$(xml "$log_file")</string>
  <key>StandardErrorPath</key>
  <string>$(xml "$log_file")</string>
</dict>
</plist>
PLIST
}

stop() {
  launchctl bootout "$domain/$service" 2>/dev/null || true
  for _ in $(seq 1 90); do
    launchctl print "$domain/$service" >/dev/null 2>&1 || return 0
    sleep 1
  done
  echo "$service did not stop." >&2
  exit 70
}

case "$verb" in
  install | plist)
    [[ $# -eq 3 ]] || usage
    [[ -f "$3" ]] || { echo "No such definition file: $3" >&2; exit 66; }
    definition="$(absolute "$3")"
    if [[ "$verb" == plist ]]; then
      plist "$definition"
      exit 0
    fi
    swift build -c release --package-path "$repo/mac/controller-core"
    "$binary" --validate-definition "$definition"
    mkdir -p "$(dirname "$plist_file")" "$(dirname "$log_file")"
    stop
    plist "$definition" > "$plist_file"
    launchctl bootstrap "$domain" "$plist_file"
    echo "Started $service. Its events are in $log_file"
    ;;
  remove)
    [[ $# -eq 2 ]] || usage
    stop
    rm -f "$plist_file"
    echo "Removed $service."
    ;;
  *)
    usage
    ;;
esac
