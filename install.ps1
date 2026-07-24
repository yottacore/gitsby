#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and installs the latest gitsby release (PowerShell edition).
.DESCRIPTION
    Shows the plan and asks first. Requires PowerShell 7+. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System -Yes
.PARAMETER System
    Install for all users (default: current user only).
.PARAMETER Yes
    Don't ask for confirmation.
.PARAMETER Ref
    Install from a branch/tag/commit instead of the latest release.
.NOTES
    Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
[CmdletBinding()]
param(
    [switch]$System,
    [switch]$Yes,
    [string]$Ref
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = 'jim-collier/gitsby'
$isRelease = -not $Ref

# No -Ref: resolve the latest release tag from the releases/latest redirect (no auth, no
# API rate limit); unauthenticated API only as fallback (60 req/hr per IP).
if (-not $Ref) {
    $location = ''
    try {
        $resp = Invoke-WebRequest -Uri "https://github.com/${repo}/releases/latest" -MaximumRedirection 0 -ErrorAction Stop
        $location = [string]$resp.Headers.Location
    } catch {
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $location = [string]$_.Exception.Response.Headers.Location }
    }
    if ($location -match '/releases/tag/([^/\s]+)') { $Ref = $Matches[1] }
}
if (-not $Ref) {
    try {
        $Ref = (Invoke-RestMethod -Uri "https://api.github.com/repos/${repo}/releases/latest").tag_name
    } catch {
        throw "Couldn't determine the latest release; pass e.g. -Ref main. GitHub may be rate-limiting; try again later. ($($_.Exception.Message))"
    }
}

# Destination: per-user by default; -System needs elevation (sudo / admin shell).
if ($IsWindows) {
    $destDir = if ($System) { Join-Path -Path $env:ProgramFiles -ChildPath 'gitsby' } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs/gitsby' }
} else {
    $destDir = if ($System) { '/usr/local/bin' } else { Join-Path -Path $HOME -ChildPath '.local/bin' }
}
$destPath = Join-Path -Path $destDir -ChildPath 'gitsby.ps1'

Write-Host ''
Write-Host '[ gitsby installer (PowerShell) ]'
Write-Host 'This will:'
Write-Host "  - Download gitsby.ps1 (${Ref}) from github.com/${repo}"
Write-Host "  - Install it to ${destPath}"
if ($System) { Write-Host '  - Need write access to that directory (run elevated / via sudo)' }
Write-Host "  - Run 'gitsby.ps1 --version' to verify"
if (-not $Yes) {
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 1 }
}

# Prefer the release asset; fall back to the file in the tagged tree.
Write-Host ''
Write-Host '[ Downloading ... ]'
# Private random subdirectory, not a predictable name in shared temp.
$tmpDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$tmpFile = Join-Path -Path $tmpDir -ChildPath 'gitsby.ps1'
$downloaded = $false
$fromReleaseAsset = $false
foreach ($url in @(
        "https://github.com/${repo}/releases/download/${Ref}/gitsby.ps1",
        "https://raw.githubusercontent.com/${repo}/${Ref}/bin/gitsby.ps1")) {
    if ($downloaded) { break }
    if (-not $isRelease -and $url -like '*releases/download*') { continue }
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpFile
        $downloaded = $true
        $fromReleaseAsset = ($url -like '*releases/download*')
    } catch {
        Write-Verbose "Fetch failed, trying next source: ${url}"
    }
}
if (-not $downloaded) {
    throw "Couldn't download gitsby.ps1 at '${Ref}'. If that release has no PowerShell build yet, use the Bash installer (install.bash) or watch the repo for the PowerShell port."
}
# Wrong-content 200s happen (captive portals, truncation); a script starts with a shebang.
if ((Get-Content -LiteralPath $tmpFile -First 1) -notmatch '^#!') { throw "Downloaded file doesn't look like a script; aborting." }

# Verify against the release's SHA256SUMS when there is one. Only the release-asset
# path can be verified; -Ref installs pull straight from the tree, unverified.
if ($fromReleaseAsset) {
    $sums = ''
    try { $sums = (Invoke-WebRequest -Uri "https://github.com/${repo}/releases/download/${Ref}/SHA256SUMS").Content } catch { $sums = '' }
    $want = ''
    foreach ($sumLine in ($sums -split "`r?`n")) {
        if ($sumLine -match '^([0-9a-fA-F]{64})\s+\*?gitsby\.ps1$') { $want = $Matches[1]; break }
    }
    if ($want) {
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmpFile).Hash
        if ($got -ne $want) { throw 'Checksum mismatch for the downloaded gitsby.ps1; aborting. (Corrupted download or tampering.)' }
        Write-Host '[ Checksum verified. ]'
    } else {
        Write-Host "Note: no SHA256SUMS for ${Ref}; skipping verification."
    }
}

try {
    Write-Host "[ Installing to ${destPath} ... ]"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Move-Item -Force -Path $tmpFile -Destination $destPath
    if (-not $IsWindows) { chmod +x $destPath }

    Write-Host '[ Verifying ... ]'
    & $destPath --version

    $pathSep = [IO.Path]::PathSeparator
    if (($env:PATH -split $pathSep) -notcontains $destDir) {
        Write-Host "Note: ${destDir} isn't on your PATH; add it to make 'gitsby.ps1' callable by name."
    }
    Write-Host ''
    Write-Host '[ Done. ]'
    Write-Host ''
} finally {
    if (Test-Path -LiteralPath $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
}


# History:
#   - 20260722 JC: Created. Until the PowerShell port ships in a release, the
#     download step reports that and points at the Bash installer.
#   - 20260724 JC: Latest-release lookup via the releases/latest redirect (API scrape
#     is now the rate-limited fallback); random private temp dir; shebang sanity check;
#     release-asset downloads verify against a SHA256SUMS asset when published; named
#     parameters throughout; trailing blank line.
