# Shared by the package updaters. Call begin_release before update_asset.
begin_release() {
  cd "$(dirname "$0")/.."
  manifest="bucket/$1.json"
  repo=$2
  release=$(gh api "repos/$repo/releases/latest")
  tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<< "$release")
  version=${tag#v}
  [[ $version =~ ^[0-9][0-9A-Za-z._+-]*$ ]] || { echo "Invalid release tag: $tag" >&2; return 1; }
  original=$(jq -ce '.' "$manifest")
  candidate=$(jq -c --arg version "$version" '.version = $version' <<< "$original")
}

update_asset() {
  local name=$1 path=$2 url digest hash
  url="https://github.com/$repo/releases/download/$tag/$name"
  digest=$(jq -er --arg name "$name" --arg url "$url" '
    [.assets[] | select(.name == $name and .browser_download_url == $url and .state == "uploaded")]
    | if length == 1 then .[0].digest // "" else error("Missing or duplicate asset: " + $name) end
  ' <<< "$release")
  if [[ -z $digest ]]; then
    hash=$(curl --fail --silent --show-error --location "$url" | sha256sum)
    hash=${hash%% *}
  elif [[ $digest =~ ^sha256:([[:xdigit:]]{64})$ ]]; then
    hash=${BASH_REMATCH[1],,}
  else
    echo "Invalid SHA-256 for $name" >&2
    return 1
  fi
  candidate=$(jq -c --argjson path "$path" --arg url "$url" --arg hash "$hash" '
    setpath($path + ["url"]; $url) | setpath($path + ["hash"]; $hash)
  ' <<< "$candidate")
}

finish_release() {
  local updated=false
  jq -e --arg entry "$1" 'all(.version, .description, .homepage, .license, .[$entry]; . != null and . != "")' <<< "$candidate" >/dev/null
  if [[ $candidate != "$original" ]]; then
    tmp=$(mktemp "$manifest.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    jq '.' <<< "$candidate" > "$tmp"
    mv "$tmp" "$manifest"
    updated=true
  fi
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf 'updated=%s\nversion=%s\n' "$updated" "$version" >> "$GITHUB_OUTPUT"
  fi
}
