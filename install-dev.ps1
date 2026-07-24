#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up a gitsby development environment (PowerShell edition).
.DESCRIPTION
    Clones the repo, checks out the 'dev' branch, and checks the tooling. Shows
    the plan and asks first. Requires PowerShell 7+ and git. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install-dev.ps1))) -Directory ~/dev/gitsby -Yes
.PARAMETER Directory
    Where to clone to (default: ./gitsby).
.PARAMETER Yes
    Don't ask for confirmation.
.NOTES
    Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
[CmdletBinding()]
param(
    [string]$Directory = './gitsby',
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = 'jim-collier/gitsby'

if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) { throw 'git is required; install it first.' }
# Option-shaped paths would bind as real git clone options; same guard as install-dev.bash.
if ($Directory -match '^-') { throw "'${Directory}' looks like an option, not a directory." }
if (Test-Path -LiteralPath $Directory) { throw "'${Directory}' already exists; pick another -Directory or remove it." }

# The local cicd pipeline (cicd/cicd.bash) is bash-based; on Windows it runs
# under WSL or Git Bash. Only git + PowerShell 7 are needed to hack on the
# (future) PowerShell port itself.
$toolNotes = @()
if (-not (Get-Command -Name bash -ErrorAction SilentlyContinue)) { $toolNotes += 'bash 5+ (for the cicd pipeline and the Bash gitsby; WSL or Git Bash on Windows)' }
if (-not (Get-Command -Name shellcheck -ErrorAction SilentlyContinue)) { $toolNotes += 'shellcheck (lint stage)' }
if (-not (Get-Command -Name markdownlint -ErrorAction SilentlyContinue)) { $toolNotes += 'markdownlint (npm install -g markdownlint-cli)' }

Write-Host ''
Write-Host '[ gitsby dev setup (PowerShell) ]'
Write-Host 'This will:'
Write-Host "  - Clone github.com/${repo} into '${Directory}' and check out the 'dev' branch"
if ($toolNotes.Count -gt 0) {
    Write-Host '  - Note tooling to install by hand if you want the full pipeline:'
    $toolNotes | ForEach-Object { Write-Host "      - $_" }
}
if (-not $Yes) {
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 1 }
}

Write-Host ''
Write-Host '[ Cloning ... ]'
git clone "https://github.com/${repo}.git" $Directory
if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
Push-Location -Path $Directory
try {
    git checkout dev 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "Note: no 'dev' branch on origin; staying on the default branch." }

    Write-Host ''
    Write-Host '[ Done. ]'
    Write-Host 'Next steps:'
    Write-Host '  - Read contributing.md and style-guide.md'
    Write-Host '  - Run the local pipeline (bash): cicd/cicd.bash --quick'
    Write-Host "  - Work on a short-named feature branch off 'dev'; PRs merge back to 'dev'"
    Write-Host ''
} finally {
    Pop-Location
}


# History:
#   - 20260722 JC: Created.
#   - 20260724 JC: Option-shaped -Directory rejected; named parameters throughout; trailing blank line.
