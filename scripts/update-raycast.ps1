param(
    [string]$ManifestPath = "bucket/raycast.json",
    [int]$TimeoutSec = 60,
    [string]$OfficialPageUrl = "https://www.raycast.com/windows",
    [string]$InstallerEntryUrl = "https://ray.so/download-windows",
    [string]$MockOfficialPagePath,
    [string]$MockInstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

function Write-WorkflowOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
}

# Browser-like UA is required: raycast.com serves a 404 error shell to unknown
# clients, which would defeat any regex extraction below.
$script:BrowserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

function New-HttpClient {
    param(
        [Parameter(Mandatory = $true)]
        [int]$TimeoutInSec
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutInSec)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd($script:BrowserUserAgent)
    return [PSCustomObject]@{ Client = $client; Handler = $handler }
}

function Get-WebContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutInSec
    )

    $pair = New-HttpClient -TimeoutInSec $TimeoutInSec
    try {
        return $pair.Client.GetStringAsync($Uri).GetAwaiter().GetResult()
    }
    finally {
        $pair.Client.Dispose()
        $pair.Handler.Dispose()
    }
}

function Save-FileWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$OutFile,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutInSec
    )

    # Returns the FINAL resolved URL after redirects, so the manifest can pin a
    # versioned/immutable URL that matches the bytes we just hashed.
    $pair = New-HttpClient -TimeoutInSec $TimeoutInSec
    try {
        $response = $pair.Client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            $resolvedUri = $response.RequestMessage.RequestUri.AbsoluteUri
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            [System.IO.File]::WriteAllBytes($OutFile, $bytes)
            return $resolvedUri
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $pair.Client.Dispose()
        $pair.Handler.Dispose()
    }
}

function Get-RaycastOfficialVersion {
    $pageContent = $null
    if ($MockOfficialPagePath) {
        if (-not (Test-Path -Path $MockOfficialPagePath)) {
            throw "Mock official page not found: $MockOfficialPagePath"
        }
        $pageContent = Get-Content -Path $MockOfficialPagePath -Raw
    }
    else {
        $pageContent = Get-WebContent -Uri $OfficialPageUrl -TimeoutInSec $TimeoutSec
    }

    # Detect the Next.js 404 shell so we fail loudly instead of silently using a
    # stale fallback (the bug that made historical hashes wrong).
    if ($pageContent -match '__next_error__' -or $pageContent -match 'NEXT_REDIRECT') {
        throw "Official Raycast page returned an error shell. Page URL may have changed: $OfficialPageUrl"
    }

    # Accept both 3-part and 4-part versions in case Raycast changes display format.
    $versionMatch = [regex]::Match($pageContent, "v(?<version>\d+\.\d+\.\d+(?:\.\d+)?)\s*(Beta)?", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $versionMatch.Success) {
        throw "Unable to detect Raycast version from official page."
    }

    return $versionMatch.Groups["version"].Value
}

if (-not (Test-Path -Path $ManifestPath)) {
    throw "Manifest file not found: $ManifestPath"
}

$officialVersion = Get-RaycastOfficialVersion

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

# Always re-download and re-hash so we can also self-heal stale url/hash even
# when version has not bumped (e.g. when a previous run wrote a fallback URL).
$tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("raycast-installer-{0}.exe" -f $officialVersion)
$resolvedUrl = $InstallerEntryUrl

try {
    if ($MockInstallerPath) {
        if (-not (Test-Path -Path $MockInstallerPath)) {
            throw "Mock installer not found: $MockInstallerPath"
        }
        Copy-Item -Path $MockInstallerPath -Destination $tempFile -Force
        Write-Host "Using mock installer from: $MockInstallerPath"
    }
    else {
        Write-Host "Downloading installer from: $InstallerEntryUrl"
        $resolvedUrl = Save-FileWithTimeout -Uri $InstallerEntryUrl -OutFile $tempFile -TimeoutInSec $TimeoutSec
        Write-Host "Resolved installer URL: $resolvedUrl"
    }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $tempFile).Hash.ToLowerInvariant()

    $manifest.version = $officialVersion
    $manifest.url = $resolvedUrl
    $manifest.hash = $hash

    $updatedManifestJson = $manifest | ConvertTo-Json -Depth 10
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ManifestPath, $updatedManifestJson, $utf8NoBom)

    Write-Host "Wrote $ManifestPath (version=$officialVersion, url=$resolvedUrl, hash=$hash)."

    # Decide "updated" purely from working-tree diff so the PR step only fires
    # when the manifest actually changed (versus the committed file in HEAD).
    $gitOutput = & git status --porcelain -- $ManifestPath 2>$null
    $hasChanges = -not [string]::IsNullOrWhiteSpace(($gitOutput | Out-String))
    if ($hasChanges) {
        Write-Host "Manifest changed compared to HEAD; will request PR."
        Write-WorkflowOutput -Name "updated" -Value "true"
    }
    else {
        Write-Host "Manifest unchanged compared to HEAD; no PR needed."
        Write-WorkflowOutput -Name "updated" -Value "false"
    }
    Write-WorkflowOutput -Name "version" -Value $officialVersion
}
finally {
    if (Test-Path -Path $tempFile) {
        Remove-Item -Path $tempFile -Force
    }
}
