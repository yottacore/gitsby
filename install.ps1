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

# No -Ref: resolve the latest release tag.
if (-not $Ref) {
    try {
        $Ref = (Invoke-RestMethod -Uri "https://api.github.com/repos/${repo}/releases/latest").tag_name
    } catch {
        throw "Couldn't determine the latest release; pass e.g. -Ref main. ($($_.Exception.Message))"
    }
}

# Destination: per-user by default; -System needs elevation (sudo / admin shell).
if ($IsWindows) {
    $destDir = if ($System) { Join-Path $env:ProgramFiles 'gitsby' } else { Join-Path $env:LOCALAPPDATA 'Programs/gitsby' }
} else {
    $destDir = if ($System) { '/usr/local/bin' } else { Join-Path $HOME '.local/bin' }
}
$destPath = Join-Path $destDir 'gitsby.ps1'

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
$tmpFile = Join-Path ([IO.Path]::GetTempPath()) "gitsby-install-$PID.ps1"
$downloaded = $false
foreach ($url in @(
        "https://github.com/${repo}/releases/download/${Ref}/gitsby.ps1",
        "https://raw.githubusercontent.com/${repo}/${Ref}/bin/gitsby.ps1")) {
    if ($downloaded) { break }
    if (-not $isRelease -and $url -like '*releases/download*') { continue }
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpFile
        $downloaded = $true
    } catch {
        Write-Verbose "Fetch failed, trying next source: ${url}"
    }
}
if (-not $downloaded) {
    throw "Couldn't download gitsby.ps1 at '${Ref}'. If that release has no PowerShell build yet, use the Bash installer (install.bash) or watch the repo for the PowerShell port."
}

try {
    Write-Host "[ Installing to ${destPath} ... ]"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Move-Item -Force $tmpFile $destPath
    if (-not $IsWindows) { chmod +x $destPath }

    Write-Host '[ Verifying ... ]'
    & $destPath --version

    $pathSep = [IO.Path]::PathSeparator
    if (($env:PATH -split $pathSep) -notcontains $destDir) {
        Write-Host "Note: ${destDir} isn't on your PATH; add it to make 'gitsby.ps1' callable by name."
    }
    Write-Host ''
    Write-Host '[ Done. ]'
} finally {
    if (Test-Path $tmpFile) { Remove-Item -Force $tmpFile }
}


# History:
#   - 20260722 JC: Created. Until the PowerShell port ships in a release, the
#     download step reports that and points at the Bash installer.
