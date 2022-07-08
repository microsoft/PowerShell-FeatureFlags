# Fail on the first error.
$ErrorActionPreference = "Stop"

# Debug info.
Write-Host "PowerShell version" $PSVersionTable.PSVersion

# As a first step, try to import the FeatureFlags module.
# When loaded, the module will try to read the schema and validate it, so some
# errors can be triggered even before loading Pester.
$ModuleName = "FeatureFlags"
Get-Module $ModuleName | Remove-Module -Force
$Module = Import-Module $PSScriptRoot\..\${ModuleName}.psd1 -Force -PassThru
if ($null -eq $Module) {
   Write-Error "Could not import $ModuleName"
   exit 1
}
Write-Host "FeatureFlags module loads successfully. Removing it."
Get-Module $ModuleName | Remove-Module -Force

# Install the required Pester version.
# We use the latest 4.x because 5.x fails to load under PowerShell 6.0.4,
# which is one of the versions we want to test.
$RequiredPesterVersion = "4.10.1"
$pesterVersions = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester" -and $_.Version -eq $RequiredPesterVersion}
$InstallPester = $false
if ($pesterVersions.Count -eq 0) {
   Write-Warning "Pester $RequiredPesterVersion not found, installing it."
   $InstallPester = $true
}
if ($InstallPester) {
   Install-Module Pester -Force -Scope CurrentUser -RequiredVersion $RequiredPesterVersion -SkipPublisherCheck
}

# Load the required Pester module.
Get-Module -Name Pester | Remove-Module
Import-Module Pester -RequiredVersion $RequiredPesterVersion

# Invoke Pester.
$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$testDir = Join-Path $parentDir -ChildPath "test"
$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}
