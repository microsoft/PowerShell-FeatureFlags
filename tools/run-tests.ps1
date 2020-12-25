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

# List Pester versions.
$pesterVersions = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester" }
$pesterVersions | % { Write-Host $_.Name $_.Version }

if ($pesterVersions.Count -eq 0) {
   Write-Warning "No Pester found, will install Pester 5.1.0"
   $InstallPester = $true
}

if ($InstallPester) {
   Install-Module Pester -Force -Scope CurrentUser -RequiredVersion 5.1.0
}

$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}