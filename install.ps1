#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and installs the gitsby binary for this platform.
.DESCRIPTION
    Shows the plan and asks first. Requires PowerShell 7+ to run; what it installs is a
    static binary and needs no PowerShell at all. Meant for one-liner use:
        irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1 | iex
    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/gitsby/main/install.ps1))) -System -Yes
.PARAMETER Target
    'user' for a per-user install (default), or 'system' for all users.
.PARAMETER Arch
    Which binary to fetch: 'amd64' or 'arm64'. Detected from this machine by default.
.PARAMETER System
    Install for all users. The same thing as -Target system.
.PARAMETER Yes
    Don't ask for confirmation.
.PARAMETER Tag
    Install a specific published release tag instead of the latest.
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
        [ValidateSet('user', 'system')][string]$Target,
        [ValidateSet('x64', 'x86_64', 'amd64', 'arm64', 'aarch64')][string]$Arch,
        [switch]$System,
        [switch]$Yes,
        # -Ref was this parameter's name while gitsby was a script installed from a tree. It
        # names a published release now, and the old spelling stays as an alias for good.
        [Alias('Ref')][ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Tag,
        # Took 'dev' or 'stable' when a branch could be installed from its tree. Bound rather
        # than dropped, so a familiar flag gets an explanation instead of a binder error.
        [string]$Release
    )

    # Windows PowerShell 5.1 is still 'powershell' on Windows and has no $IsWindows, which
    # StrictMode turns into an undefined-variable error further down - so say it plainly here.
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "This installer needs PowerShell 7+; this is $($PSVersionTable.PSVersion). Install it: 'winget install --id Microsoft.PowerShell' on Windows, or see https://aka.ms/powershell."
    }
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repo = 'jim-collier/gitsby'

    # '-Release dev' installed the tip of a branch, which meant downloading a script. There is
    # no script to download now, and a branch has no build behind it.
    if ($Release -eq 'dev') {
        throw "There is no '-Release dev' any more: gitsby is a compiled binary, and a branch has no published build. Take a release with '-Tag TAG', or build the tip yourself: git clone https://github.com/${repo}.git; cd gitsby/src-go; go build -o gitsby ."
    }
    if ($Release -and $Release -ne 'stable') {
        throw "-Release only ever took 'dev' or 'stable', and now takes neither; use '-Tag TAG' for a specific release."
    }
    # The tag lands in a download URL, so a path-shaped one walks out of this repo and installs
    # somebody else's binary while the plan on screen still names ours. ValidatePattern admits
    # '..' and a leading '/', so both are checked here. Reads as a harmless version selector,
    # which is exactly why the confirm prompt is no protection.
    if ($Tag -and ($Tag -match '(^|/)\.\.(/|$)' -or $Tag -match '^/' -or $Tag -match '//')) {
        throw "-Tag names a published release, not a path (got '${Tag}')."
    }
    $installSystemWide = $System.IsPresent -or ($Target -eq 'system')

    # Which asset belongs to this machine. Go's own spelling, since that is what the release
    # is named by. Anything else falls through to the SHA256SUMS lookup below, which is the
    # authority on what this release actually published.
    $goOs = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } elseif ($IsLinux) { 'linux' } else { 'unknown' }
    # Detection lands in its own variable rather than back in $Arch: assigning to a parameter
    # re-runs its ValidateSet, so an x86 or 32-bit ARM box would die with a binder error
    # instead of being told what this release does publish.
    $archName = if ($Arch) { $Arch } else {
        switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
            'X64'   { 'amd64' }
            'Arm64' { 'arm64' }
            default { "$_".ToLowerInvariant() }
        }
    }
    # -Arch used to be accepted and ignored, back when the product was one script that ran
    # everywhere. It picks the binary now, so spell the two the release actually publishes.
    $goArch = switch ($archName) {
        { $_ -in 'x64', 'x86_64', 'amd64' } { 'amd64'; break }
        { $_ -in 'arm64', 'aarch64' }       { 'arm64'; break }
        default                             { $archName }
    }
    $asset = "gitsby-${goOs}-${goArch}"
    if ($IsWindows) { $asset += '.exe' }

    # No -Tag: resolve the latest release from the releases/latest redirect (no auth, no
    # API rate limit); unauthenticated API only as fallback (60 req/hr per IP).
    # Resolved into its own variable for the same reason as $archName: a scraped tag assigned
    # back to $Tag re-runs its ValidatePattern, which turns the check below into dead code and
    # reports a malformed tag as whatever the surrounding catch happens to say.
    $tagName = $Tag
    if (-not $tagName) {
        $location = ''
        try {
            $resp = Invoke-WebRequest -Uri "https://github.com/${repo}/releases/latest" -MaximumRedirection 0 -ErrorAction Stop
            $location = [string]$resp.Headers.Location
        } catch {
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $location = [string]$_.Exception.Response.Headers.Location }
        }
        if ($location -match '/releases/tag/([^/\s]+)') { $tagName = $Matches[1] }
    }
    if (-not $tagName) {
        try {
            $tagName = (Invoke-RestMethod -Uri "https://api.github.com/repos/${repo}/releases/latest").tag_name
        } catch {
            throw "Couldn't determine the latest release. GitHub may be rate-limiting; try again later. ($($_.Exception.Message))"
        }
    }
    # Scraped from a redirect header, so check it the same way as a typed one before it reaches a URL.
    if ($tagName -notmatch '^[A-Za-z0-9._/-]+$') { throw "The resolved release tag ('${tagName}') isn't a plain git tag; aborting." }

    # SHA256SUMS decides two things at once, and it is a few hundred bytes: whether this
    # release publishes a binary for this platform, and what that binary should hash to.
    # Fetching it up front means the plan can promise a specific file, before anything large
    # is downloaded. Every install path here is a release asset, so every one is verified -
    # there is no unverified route left to fall back to.
    $base = "https://github.com/${repo}/releases/download/${tagName}"
    $sums = ''
    try {
        # GitHub serves SHA256SUMS as application/octet-stream, and Invoke-WebRequest returns
        # .Content as bytes for anything it doesn't consider text. Splitting those into lines
        # matched nothing, so every default install skipped verification and said there was no
        # SHA256SUMS - which wasn't true.
        $body = (Invoke-WebRequest -Uri "${base}/SHA256SUMS").Content
        $sums = if ($body -is [byte[]]) { [Text.Encoding]::UTF8.GetString($body) } else { [string]$body }
    } catch { $sums = '' }
    if (-not $sums) {
        throw "Release ${tagName} publishes no SHA256SUMS, so nothing here can be verified. (A release published seconds ago may not be servable yet; try again shortly.)"
    }
    $want = ''
    $published = @()
    foreach ($sumLine in ($sums -split "`r?`n")) {
        if ($sumLine -match '^([0-9a-fA-F]{64})\s+\*?(gitsby-\S+)$') {
            $published += ($Matches[2] -replace '^gitsby-', '' -replace '\.exe$', '')
            if ($Matches[2] -eq $asset) { $want = $Matches[1] }
        }
    }
    if (-not $want) {
        $alsoRan = if ($published) { " It publishes: $($published -join ', ')." } else { '' }
        throw "Release ${tagName} publishes no gitsby binary for ${goOs}/${goArch}.${alsoRan} Build it for yours instead - the module is pure Go with no dependencies: git clone https://github.com/${repo}.git; cd gitsby/src-go; go build -o gitsby ."
    }

    # Destination: per-user by default; -System needs elevation (sudo / admin shell).
    if ($IsWindows) {
        $destDir = if ($installSystemWide) { Join-Path -Path $env:ProgramFiles -ChildPath 'gitsby' } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs/gitsby' }
        $destPath = Join-Path -Path $destDir -ChildPath 'gitsby.exe'
    } else {
        $destDir = if ($installSystemWide) { '/usr/local/bin' } else { Join-Path -Path $HOME -ChildPath '.local/bin' }
        $destPath = Join-Path -Path $destDir -ChildPath 'gitsby'
    }

    Write-Host ''
    Write-Host '[ gitsby installer (PowerShell) ]'
    Write-Host 'This will:'
    Write-Host "  - Download ${asset} (${tagName}) from github.com/${repo}"
    Write-Host '  - Verify it against the release''s published SHA256SUMS'
    Write-Host "  - Install it to ${destPath}"
    if ($installSystemWide) { Write-Host '  - Need write access to that directory (run elevated / via sudo)' }
    # Windows puts nothing on PATH for you, so without this the install finishes with a program
    # that cannot be run by name. On *nix the destination is a conventional bin dir already.
    if ($IsWindows -and (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $destDir)) {
        $pathScopeLabel = if ($installSystemWide) { 'system' } else { 'account' }
        Write-Host "  - Add ${destDir} to your ${pathScopeLabel} PATH (new shells only; this one is unchanged)"
    }
    Write-Host "  - Run 'gitsby --version' to verify"
    if (-not $Yes) {
        $answer = Read-Host 'Continue? [y/N]'
        # Cast: Read-Host returns AutomationNull at EOF, and -notmatch on that yields an empty
        # (falsy) collection - so a non-tty stdin would sail past the prompt unasked.
        # throw, not exit: 'exit' inside iex or a scriptblock ends the CALLER's session.
        if ("${answer}" -notmatch '^(y|yes)$') { throw 'Aborted.' }
    }

    Write-Host ''
    Write-Host '[ Downloading ... ]'
    # Private random subdirectory, not a predictable name in shared temp.
    $tmpDir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    try {
        $tmpFile = Join-Path -Path $tmpDir -ChildPath $asset
        try {
            Invoke-WebRequest -Uri "${base}/${asset}" -OutFile $tmpFile
        } catch {
            throw "Couldn't download ${asset} from release ${tagName}. ($($_.Exception.Message))"
        }
        if ((Get-Item -LiteralPath $tmpFile).Length -eq 0) { throw "Downloaded ${asset} is empty; aborting." }
        # A captive portal or a proxy answers with a page, not a binary. It would fail the
        # checksum anyway, but as tampering rather than as the network problem it is.
        $firstByte = Get-Content -LiteralPath $tmpFile -AsByteStream -TotalCount 1
        if ($firstByte -eq [byte][char]'<') {
            throw 'The download came back as a web page, not a binary - something between here and GitHub is intercepting it.'
        }

        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmpFile).Hash
        if ($got -ne $want) { throw "Checksum mismatch for ${asset}; aborting. (Corrupted download or tampering.)" }
        Write-Host '[ Checksum verified. ]'

        Write-Host "[ Installing to ${destPath} ... ]"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Move-Item -Force -LiteralPath $tmpFile -Destination $destPath
        if (-not $IsWindows) { chmod +x $destPath }

        Write-Host '[ Verifying ... ]'
        & $destPath --version

        $pathSep = [IO.Path]::PathSeparator
        if (($env:PATH -split $pathSep) -notcontains $destDir) {
            if ($IsWindows) {
                # Persist it, as promised in the plan.
                $pathScope = if ($installSystemWide) { 'Machine' } else { 'User' }
                # Straight at the registry rather than [Environment]::GetEnvironmentVariable,
                # which hands back the EXPANDED PATH: writing that back would bake entries like
                # %USERPROFILE%\bin in as literals, permanently, for a PATH we only meant to
                # append to. Reading it raw and putting back the kind it already had leaves
                # every other entry exactly as it was.
                $pathKeyPath = if ($installSystemWide) { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } else { 'HKCU:\Environment' }
                try {
                    $pathKey = Get-Item -LiteralPath $pathKeyPath
                    $stored = [string]$pathKey.GetValue('PATH', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if (($stored -split $pathSep) -notcontains $destDir) {
                        $joined = if ([string]::IsNullOrEmpty($stored)) { $destDir } else { $stored.TrimEnd($pathSep) + $pathSep + $destDir }
                        $storedKind = if ($stored) { $pathKey.GetValueKind('PATH') }
                            elseif ($joined -match '%') { [Microsoft.Win32.RegistryValueKind]::ExpandString }
                            else { [Microsoft.Win32.RegistryValueKind]::String }
                        Set-ItemProperty -LiteralPath $pathKeyPath -Name 'PATH' -Value $joined -Type $storedKind
                    }
                    $env:PATH = $env:PATH.TrimEnd($pathSep) + $pathSep + $destDir
                    Write-Host "[ Added ${destDir} to your ${pathScope} PATH. Open a new shell to pick it up. ]"
                } catch {
                    Write-Host "Note: couldn't update PATH ($($_.Exception.Message)). Add ${destDir} to it to run 'gitsby' by name."
                }
            } else {
                Write-Host "Note: ${destDir} isn't on your PATH; add it in your shell profile."
            }
        }
        Write-Host ''
        Write-Host '[ Done. ]'
        Write-Host ''
    } finally {
        ## LiteralPath, like every other removal in the tree: the temp path is ours, but a bracket
        ## anywhere in it would otherwise be read as a wildcard rather than as a character.
        if ($tmpDir -and (Test-Path -LiteralPath $tmpDir)) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
    }
}

# A function, not top-level script text: 'iex' evaluates a top-level param() block in the
# caller's scope, where [ValidateSet] validates against its own empty default and dies before
# anything runs - so the documented one-liner never worked. Splatting $args keeps every
# documented shape binding: -Tag after the scriptblock form, and pwsh -File install.ps1 -Yes.
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
#   - 20260731 JC: SHA256SUMS is decoded from bytes before it's read. GitHub serves it as
#     octet-stream, so the response body arrived as a byte array and no checksum was ever
#     found - the default install path had been unverified since the check was added.
#   - 20260819 JC: Installs the binary for this platform, as gitsby.exe on Windows. -Arch is
#     real (it picks the asset) and -Ref is now -Tag, naming a release rather than any git
#     ref. -Release is bound only to explain itself. Every route is a release asset now, so
#     every route is verified and the unverified branch of the plan no longer exists.
#     SHA256SUMS is fetched before the plan is printed, because it is what says whether this
#     platform has a binary at all - and it names the ones that do when this one doesn't.
#   - 20260819 JC: Detection no longer lands back in -Arch and -Tag. Assigning to a parameter
#     re-runs its own validation, so an x86 box and a malformed scraped tag each died in the
#     binder instead of reaching the message written for them. PATH is now read raw from the
#     registry before it is rewritten - the expanded copy would have baked %USERPROFILE%-style
#     entries in as literals, for good, on a PATH we only meant to append to.
