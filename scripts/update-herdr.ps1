$ErrorActionPreference = 'Stop'

$repository = 'herdrdev/herdr'
$manifestPath = Join-Path $PSScriptRoot '..\bucket\herdr.json'
$apiHeaders = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'chamione-scoop-bucket'
}

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" -Headers $apiHeaders
if ($release.draft -or $release.prerelease) {
    throw "The latest GitHub release is not a stable release."
}

$asset = @($release.assets | Where-Object name -eq 'herdr-windows-x86_64.zip') | Select-Object -First 1
if (-not $asset) {
    throw "Could not find herdr-windows-x86_64.zip in release $($release.tag_name)."
}

$version = $release.tag_name.TrimStart('v')
$url = $asset.browser_download_url
$hash = $asset.digest
if ($hash -match '^sha256:') {
    $hash = $hash.Substring(7)
}

if ([string]::IsNullOrWhiteSpace($hash)) {
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "herdr-$version.zip"
    try {
        Invoke-WebRequest -Uri $url -Headers $apiHeaders -OutFile $tempPath
        $hash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}
$hash = $hash.ToLowerInvariant()

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$changed = "$($manifest.version)" -ne $version -or "$($manifest.url)" -ne $url -or "$($manifest.hash)" -ne $hash
if ($changed) {
    $manifest.version = $version
    $manifest.url = $url
    $manifest.hash = $hash
    $json = $manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

if ($env:GITHUB_OUTPUT) {
    "updated=$($changed.ToString().ToLowerInvariant())" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "version=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

Write-Host "Herdr manifest: version=$version updated=$changed hash=$hash"
