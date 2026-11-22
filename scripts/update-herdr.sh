#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/release.sh"

begin_release herdr herdrdev/herdr
update_asset herdr-windows-x86_64.zip '[]'
finish_release bin
