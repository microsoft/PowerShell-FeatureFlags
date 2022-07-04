# Mostly for use of CI/CD. Install Pester and run tests.
param (
  # Set to true to install Pester 5.1.0, regardless of whether a Pester version
  # is present in the environment.
  [switch] $InstallPester = $false
)

$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$testDir = Join-Path $parentDir -ChildPath "test"

# Debug info.
$PSVersionTable | Out-String
$RequiredPesterVersion = "5.3.3"

$pesterVersions = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester" -and $_.Version -eq $RequiredPesterVersion}

if ($pesterVersions.Count -eq 0) {
   Write-Warning "Pester $RequiredPesterVersion not found, installing it."
   $InstallPester = $true
}

if ($InstallPester) {
   Install-Module Pester -Force -Scope CurrentUser -RequiredVersion $RequiredPesterVersion -SkipPublisherCheck
}

Get-Module -Name Pester | Remove-Module
Import-Module Pester -RequiredVersion $RequiredPesterVersion

$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}