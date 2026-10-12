$ErrorActionPreference = 'Stop'

$repository = 'rullerzhou-afk/clawd-on-desk'
$manifestPath = Join-Path $PSScriptRoot '..\bucket\clawd-on-desk.json'
$apiHeaders = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'chamione-scoop-bucket'
}

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" -Headers $apiHeaders
if ($release.draft -or $release.prerelease) {
    throw "The latest GitHub release is not a stable release."
}

$version = $release.tag_name.TrimStart('v')
$assetNames = @{
    '64bit' = "Clawd-on-Desk-Setup-$version-x64.exe"
    'arm64' = "Clawd-on-Desk-Setup-$version-arm64.exe"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$changed = "$($manifest.version)" -ne $version

foreach ($architecture in $assetNames.Keys) {
    $assetName = $assetNames[$architecture]
    $asset = @($release.assets | Where-Object name -eq $assetName) | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find $assetName in release $($release.tag_name)."
    }

    $url = $asset.browser_download_url
    $hash = $asset.digest
    if ($hash -match '^sha256:') {
        $hash = $hash.Substring(7)
    }

    if ([string]::IsNullOrWhiteSpace($hash)) {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "clawd-on-desk-$version-$architecture.exe"
        try {
            Invoke-WebRequest -Uri $url -Headers $apiHeaders -OutFile $tempPath
            $hash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
        }
        finally {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
    $hash = $hash.ToLowerInvariant()

    $target = $manifest.architecture.PSObject.Properties[$architecture].Value
    if ("$($target.url)" -ne $url -or "$($target.hash)" -ne $hash) {
        $target.url = $url
        $target.hash = $hash
        $changed = $true
    }
}

if ($changed) {
    $manifest.version = $version
    $json = $manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

if ($env:GITHUB_OUTPUT) {
    "updated=$($changed.ToString().ToLowerInvariant())" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "version=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

Write-Host "Clawd on Desk manifest: version=$version updated=$changed"
