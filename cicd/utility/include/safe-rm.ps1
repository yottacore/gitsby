## fSafeRm PATH: the guard for stage 7's folder on a Windows box. remote-tests.bash sends it
## with -EncodedCommand, less these comments, and a call after it. Windows PowerShell 5.1, which
## every box has. One folder right under %TEMP%, named for a stage 7 run, and not a link. Both
## sides spelled by Get-Item, so a short 8.3 temp path compares the same, as in install.ps1.
## rmdir still does the removal, as before the guard, since it removes a link inside the folder
## rather than follow it. Its exit code says little, so the folder still there is the failure,
## and its output goes nowhere, since anything written would join the boolean. A path with a
## character cmd acts on (&|<>^%"()) is refused, since 5.1 quotes an argument only for a space.
## History at the bottom.
##
## Copyright (C) 2026 Jim Collier
## Licensed under The MIT License (MIT). Full text at:
##     https://mit-license.org/
## SPDX-License-Identifier: MIT

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function fSafeRm([string]$p) {
    $why = ''
    $item = $null
    if (-not $p -or $p.Contains('..') -or $p -match "[`r`n]") { $why = 'bad path' }
    elseif (-not (Test-Path -LiteralPath $p -PathType Container)) { $why = 'not there' }
    else {
        $item = Get-Item -LiteralPath $p -Force
        $root = (Get-Item -LiteralPath $env:TEMP -Force).FullName.TrimEnd('\', '/')
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $why = 'a link' }
        elseif ($item.FullName -match '[&|<>^%"()]') { $why = 'a character cmd would act on' }
        elseif ($item.Parent.FullName.TrimEnd('\', '/') -ne $root -or $item.Name -notmatch '^test_gitsby_[0-9-]+$') { $why = 'not a stage 7 folder right under the temp folder' }
    }
    if ($why) { [Console]::Error.WriteLine("safe-rm: refused, ${why}: $p"); return $false }
    $null = & cmd.exe /d /c rmdir /s /q $item.FullName
    if (Test-Path -LiteralPath $item.FullName) { [Console]::Error.WriteLine("safe-rm: some of $p would not go"); return $false }
    [Console]::Out.WriteLine("removed $p")
    return $true
}


##	History:
##		- 2026-11-06 JC: Created, for stage 7's rmdir on the Windows box.
##		- 2026-11-07 JC: rmdir's output stays out of the return value, and the header has the copyright and license.
##		- 2026-11-11 JC: A path with a character cmd acts on is refused, not passed on to rmdir unquoted.
