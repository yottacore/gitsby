#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and installs the latest gitsby release (PowerShell edition).
.DESCRIPTION
    Shows the plan and asks first. Requires PowerShell 7+. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System -Yes
.PARAMETER Release
    Which build: 'stable' (the latest release, default) or 'dev' (the tip of the dev branch).
.PARAMETER Target
    'user' for a per-user install (default), or 'system' for all users.
.PARAMETER Arch
    Accepted for consistency with other installers, and has no effect here: gitsby is a
    script, so the same file runs on every architecture.
.PARAMETER System
    Install for all users. The same thing as -Target system.
.PARAMETER Yes
    Don't ask for confirmation.
.PARAMETER Ref
    Install from a specific branch/tag/commit instead of the latest release.
.NOTES
    Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)
    Licensed under The MIT License (MIT). Full text at: https://mit-license.org/
    SPDX-License-Identifier: MIT
    History: at bottom of script.
#>
function Install-Gitsby {
    # Attribute lives inside the function, not at file scope: the file is also read as text
    # and evaluated (iex / scriptblock), where a top-level attribute is a parse error.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'A BOM breaks the shebang, and survives irm into iex; file is UTF-8 without BOM.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; console text is the point.')]
    [CmdletBinding()]
    param(
        [ValidateSet('dev', 'stable')][string]$Release,
        [ValidateSet('user', 'system')][string]$Target,
        [ValidateSet('x64', 'x86_64', 'amd64', 'arm64', 'aarch64')][string]$Arch,
        [switch]$System,
        [switch]$Yes,
        [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Ref
    )

    # Windows PowerShell 5.1 is still 'powershell' on Windows and has no $IsWindows, which
    # StrictMode turns into an undefined-variable error further down - so say it plainly here.
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This installer needs PowerShell 7+; this is $($PSVersionTable.PSVersion). Install it: 'winget install --id Microsoft.PowerShell' on Windows, or see https://aka.ms/powershell."
    }
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repo = 'jim-collier/gitsby'

    # -Release is the friendly spelling; -Ref is the escape hatch. Both at once is ambiguous.
    if ($Release -and $Ref) { throw 'Use -Release or -Ref, not both.' }
    if ($Release -eq 'dev') { $Ref = 'dev' }
    # The ref lands in a download URL, so a path-shaped one walks out of this repo and installs
    # somebody else's script while the plan on screen still names ours. ValidatePattern admits
    # '..' and a leading '/', so both are checked here. Reads as a harmless branch selector,
    # which is exactly why the confirm prompt is no protection.
    if ($Ref -and ($Ref -match '(^|/)\.\.(/|$)' -or $Ref -match '^/' -or $Ref -match '//')) {
        throw "-Ref names a branch, tag or commit, not a path (got '${Ref}')."
    }
    $isRelease = -not $Ref
    $installSystemWide = $System.IsPresent -or ($Target -eq 'system')

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
    # Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
    if ($Ref -notmatch '^[A-Za-z0-9._/-]+$') { throw "The resolved release tag ('${Ref}') isn't a plain git ref; aborting." }

    # Destination: per-user by default; -System needs elevation (sudo / admin shell).
    if ($IsWindows) {
        $destDir = if ($installSystemWide) { Join-Path -Path $env:ProgramFiles -ChildPath 'gitsby' } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs/gitsby' }
    } else {
        $destDir = if ($installSystemWide) { '/usr/local/bin' } else { Join-Path -Path $HOME -ChildPath '.local/bin' }
    }
    $destPath = Join-Path -Path $destDir -ChildPath 'gitsby.ps1'

    Write-Host ''
    Write-Host '[ gitsby installer (PowerShell) ]'
    Write-Host 'This will:'
    Write-Host "  - Download gitsby.ps1 (${Ref}) from github.com/${repo}"
    if ($Arch) { Write-Host "  - Ignore -Arch ${Arch}: gitsby is a script, so the same file runs on every architecture" }
    Write-Host "  - Install it to ${destPath}"
    if ($installSystemWide) { Write-Host '  - Need write access to that directory (run elevated / via sudo)' }
    Write-Host "  - Run 'gitsby.ps1 --version' to verify"
    if (-not $Yes) {
        $answer = Read-Host 'Continue? [y/N]'
        # Cast: Read-Host returns AutomationNull at EOF, and -notmatch on that yields an empty
        # (falsy) collection - so a non-tty stdin would sail past the prompt unasked.
        # throw, not exit: 'exit' inside iex or a scriptblock ends the CALLER's session.
        if ("${answer}" -notmatch '^(y|yes)$') { throw 'Aborted.' }
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
        throw "Couldn't download gitsby.ps1 at '${Ref}'. (Releases before v2 predate the current layout; try '-Release dev'.)"
    }
    # Say so: only the release asset can be checked against SHA256SUMS, and asking for a
    # release and quietly getting an unverified copy of the tree is not what was agreed.
    if ($isRelease -and -not $fromReleaseAsset) {
        Write-Host "Note: no release asset for ${Ref}; installing bin/gitsby.ps1 from the tagged tree, unverified."
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
}

# A function, not top-level script text: 'iex' evaluates a top-level param() block in the
# caller's scope, where [ValidateSet] validates against its own empty default and dies before
# anything runs - so the documented one-liner never worked. Splatting $args keeps every
# documented shape binding: -Ref after the scriptblock form, and pwsh -File install.ps1 -Yes.
try {
    Install-Gitsby @args
} catch {
    # Run from a file: report plainly and exit nonzero, so callers and CI see the failure -
    # a parameter-binding error against @args would otherwise leave the exit code at 0.
    # Evaluated as text (iex / scriptblock): rethrow, because 'exit' would end the session.
    if ($PSCommandPath) {
        [Console]::Error.WriteLine("install.ps1: $($_.Exception.Message)")
        exit 1
    }
    throw
}


# History:
#   - 20260722 JC: Created.
#   - 20260724 JC: Latest-release lookup via the releases/latest redirect (API scrape
#     is now the rate-limited fallback); random private temp dir; shebang sanity check;
#     release-asset downloads verify against a SHA256SUMS asset when published; named
#     parameters throughout; trailing blank line.
#   - 20260727 JC: Options now spelled -Release, -Target and -Arch, to match the other
#     installers. -System and -Ref still work.
#   - 20260727 JC: Body wrapped in a function: as top-level text the param() block never
#     bound (its ValidateSet validated its own empty default and died), a decline ended the
#     caller's session, and StrictMode leaked into it. Refuses at EOF instead of proceeding.
#     PowerShell 7 is now checked before anything reads $IsWindows.
#   - 20260728 JC: The failed-download message names '-Release dev', like install.bash's does. It used to send you to the Bash installer, which resolves the same stale release and fails the same way.
