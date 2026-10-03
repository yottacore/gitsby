# PSScriptAnalyzer settings for the first-party .ps1 files. cicd.bash stage 1 and editors both
# read this. No Severity filter: one would also drop parse errors.
#
# PSUseConsistentIndentation is left off. Indentation stays four spaces, and the rule flags the
# hand-aligned continuation lines in install.ps1, which are not reindented to suit it.
@{
    Rules = @{
        # The installer has to run on Windows PowerShell 5.1, which is what a fresh Windows box
        # has. Nothing else here checks the syntax against it.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
