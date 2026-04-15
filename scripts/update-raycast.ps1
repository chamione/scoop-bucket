param(
    [string]$ManifestPath = "bucket/raycast.json",
    [int]$TimeoutSec = 30,
    [string]$OfficialPageUrl = "https://www.raycast.com/download-windows",
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

function Get-WebContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutInSec
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutInSec)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("raycast-bucket-updater/1.0")

    try {
        return $client.GetStringAsync($Uri).GetAwaiter().GetResult()
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
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

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutInSec)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("raycast-bucket-updater/1.0")

    try {
        $bytes = $client.GetByteArrayAsync($Uri).GetAwaiter().GetResult()
        [System.IO.File]::WriteAllBytes($OutFile, $bytes)
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-RaycastOfficialInfo {
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

    $versionMatch = [regex]::Match($pageContent, "v(?<version>\d+\.\d+\.\d+\.\d+)\s*(Beta)?", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $versionMatch.Success) {
        throw "Unable to detect Raycast version from official page."
    }

    $urlMatch = [regex]::Match($pageContent, "https://get\.microsoft\.com/installer/download/[A-Z0-9]+(?:#/[A-Za-z0-9\-_\.]+)?", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $installerUrl = "https://get.microsoft.com/installer/download/9PFXXSHC64H3#/RaycastInstaller.exe"
    if ($urlMatch.Success) {
        $installerUrl = $urlMatch.Value
    }

    return @{
        Version = $versionMatch.Groups["version"].Value
        InstallerUrl = $installerUrl
    }
}

if (-not (Test-Path -Path $ManifestPath)) {
    throw "Manifest file not found: $ManifestPath"
}

$officialInfo = Get-RaycastOfficialInfo
$officialVersion = $officialInfo.Version
$installerUrl = $officialInfo.InstallerUrl

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
$needsUpdate = ($manifest.version -ne $officialVersion) -or ($manifest.url -ne $installerUrl)

if (-not $needsUpdate) {
    Write-Host "Raycast manifest is already up to date at version $officialVersion."
    Write-WorkflowOutput -Name "updated" -Value "false"
    Write-WorkflowOutput -Name "version" -Value $officialVersion
    exit 0
}

$tempFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("raycast-installer-{0}.exe" -f $officialVersion)

try {
    if ($MockInstallerPath) {
        if (-not (Test-Path -Path $MockInstallerPath)) {
            throw "Mock installer not found: $MockInstallerPath"
        }
        Copy-Item -Path $MockInstallerPath -Destination $tempFile -Force
        Write-Host "Using mock installer from: $MockInstallerPath"
    }
    else {
        Write-Host "Downloading installer from: $installerUrl"
        Save-FileWithTimeout -Uri $installerUrl -OutFile $tempFile -TimeoutInSec $TimeoutSec
    }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $tempFile).Hash.ToLowerInvariant()

    $manifest.version = $officialVersion
    $manifest.url = $installerUrl
    $manifest.hash = $hash

    $updatedManifestJson = $manifest | ConvertTo-Json -Depth 10
    Set-Content -Path $ManifestPath -Value $updatedManifestJson -Encoding utf8

    Write-Host "Updated $ManifestPath to version $officialVersion."
    Write-WorkflowOutput -Name "updated" -Value "true"
    Write-WorkflowOutput -Name "version" -Value $officialVersion
}
finally {
    if (Test-Path -Path $tempFile) {
        Remove-Item -Path $tempFile -Force
    }
}
