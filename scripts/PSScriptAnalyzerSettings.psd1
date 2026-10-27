@{
    # PSScriptAnalyzer settings for scripts in this repository, used by the
    # psscriptanalyzer pre-commit hook (scripts/dev/Invoke-PSScriptAnalyzer.ps1).
    # All default rules run; errors and warnings fail the commit.
    Severity = @('Error', 'Warning')
}
