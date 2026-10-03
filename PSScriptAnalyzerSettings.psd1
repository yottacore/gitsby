# PSScriptAnalyzer settings for the first-party .ps1 files. cicd.bash stage 1 and editors both
# read this. No Severity filter: one would also drop parse errors.
@{
    Rules = @{
        # The installer has to run on Windows PowerShell 5.1, which is what a fresh Windows box
        # has. Nothing else here checks the syntax against it.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        # Four spaces, as the files already are. A continuation line such as a 'catch' or
        # 'else' on its own line sits at the block's indent, not under what it continues.
        PSUseConsistentIndentation = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }
    }
}
