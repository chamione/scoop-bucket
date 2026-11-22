#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/release.sh"

begin_release rebased DetachHead/rebased
update_asset rebased.exe '[]'
finish_release installer
