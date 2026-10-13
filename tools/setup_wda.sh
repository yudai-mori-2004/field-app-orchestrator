#!/bin/bash
# Fetches WebDriverAgent and builds it once for the iPhones. field-app runs
# this build on each iPhone with xcodebuild.
#
# usage: FAO_DEVELOPMENT_TEAM=<Team ID> tools/setup_wda.sh [iPhone UDID]
#
# Give the UDID of a connected iPhone the first time it is used, so that
# Xcode registers it with the team.

set -euo pipefail

version="16.15.0"
integrity="sha512-17AesL9oajcUfOgICnMFAF6wWUEML23MwhsHWsTUXOepIdBZm1+vQvhSFfpiGIG3WEo12/xm8ILH3FKLrERZhg=="
bundle_id="dev.fieldapporchestrator.WebDriverAgentRunner"

team="${FAO_DEVELOPMENT_TEAM:-}"
if [[ -z "$team" ]]; then
  echo "Set FAO_DEVELOPMENT_TEAM to the Team ID that signs WebDriverAgent." >&2
  exit 64
fi
destination="generic/platform=iOS"
if [[ $# -gt 0 ]]; then
  destination="id=$1"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wda_dir="$(cd "$script_dir/.." && pwd)/.wda"
rm -rf "$wda_dir"
mkdir -p "$wda_dir/source"

archive="$wda_dir/webdriveragent.tgz"
curl --fail --silent --show-error --location \
  "https://registry.npmjs.org/appium-webdriveragent/-/appium-webdriveragent-$version.tgz" \
  --output "$archive"
if [[ "sha512-$(openssl dgst -sha512 -binary "$archive" | base64)" != "$integrity" ]]; then
  echo "The downloaded WebDriverAgent does not match its checksum." >&2
  exit 65
fi
tar -xzf "$archive" -C "$wda_dir/source" --strip-components 1

xcodebuild build-for-testing \
  -project "$wda_dir/source/WebDriverAgent.xcodeproj" \
  -scheme WebDriverAgentRunner \
  -destination "$destination" \
  -derivedDataPath "$wda_dir" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_IDENTITY="Apple Development" \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  GCC_TREAT_WARNINGS_AS_ERRORS=0 \
  COMPILER_INDEX_STORE_ENABLE=NO

ls "$wda_dir"/Build/Products/*.xctestrun
