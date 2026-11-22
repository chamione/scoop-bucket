#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
manifest=bucket/claude-cage.json
repo=Lee-xeo/Claude-Cage
release=$(gh api "repos/$repo/releases/latest")
tag=$(jq -er '.tag_name' <<< "$release")
if [[ ! $tag =~ ^v[0-9]+([.][0-9]+)+$ ]]; then
  echo "Unexpected release tag: $tag" >&2
  exit 1
fi

version=${tag#v}
name="Cage-$version-windows-amd64-setup.exe"
url="https://github.com/$repo/releases/download/$tag/$name"
hash=$(jq -er --arg url "$url" '
  [.assets[] | select(.browser_download_url == $url and .state == "uploaded")]
  | select(length == 1) | .[0].digest
  | capture("^sha256:(?<hash>[0-9a-f]{64})$").hash
' <<< "$release")

if jq -e --arg v "$version" --arg url "$url" --arg hash "$hash" '
  .version == $v and .architecture["64bit"] == {url: $url, hash: $hash}
' "$manifest" >/dev/null; then
  exit 0
fi

tmp=$(mktemp "$manifest.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --arg v "$version" --arg url "$url" --arg hash "$hash" '
  .version = $v | .architecture["64bit"] = {url: $url, hash: $hash}
' "$manifest" > "$tmp"
mv "$tmp" "$manifest"
