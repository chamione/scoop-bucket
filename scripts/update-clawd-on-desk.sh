#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/release.sh"

begin_release clawd-on-desk rullerzhou-afk/clawd-on-desk
update_asset "Clawd-on-Desk-Setup-$version-x64.exe" '["architecture","64bit"]'
update_asset "Clawd-on-Desk-Setup-$version-arm64.exe" '["architecture","arm64"]'
finish_release installer
