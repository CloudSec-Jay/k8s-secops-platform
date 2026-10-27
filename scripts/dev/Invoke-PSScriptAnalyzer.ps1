<#
.SYNOPSIS
    pre-commit hook: lint PowerShell files with PSScriptAnalyzer.

.DESCRIPTION
    Runs inside the pinned mcr.microsoft.com/powershell container declared in
    .pre-commit-config.yaml, so neither the workstation nor CI needs pwsh
    installed. Installs the pinned PSScriptAnalyzer version into the
    container's throwaway HOME, analyzes each file passed by pre-commit with
    scripts/PSScriptAnalyzerSettings.psd1, and exits 1 if any finding remains.
#>
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$analyzerVersion = '1.25.0'
$settings = Join-Path $PSScriptRoot '..' 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -EQ $analyzerVersion)) {
    Install-PSResource -Name PSScriptAnalyzer -Version $analyzerVersion -Repository PSGallery -TrustRepository -Scope CurrentUser -Quiet
}
Import-Module PSScriptAnalyzer -RequiredVersion $analyzerVersion

$findings = foreach ($file in $Path) {
    Invoke-ScriptAnalyzer -Path $file -Settings $settings
}

if ($findings) {
    $findings |
        Sort-Object ScriptName, Line |
        Format-Table -AutoSize -Wrap Severity, RuleName, ScriptName, Line, Message |
        Out-String -Width 200 |
        Write-Output
    exit 1
}
