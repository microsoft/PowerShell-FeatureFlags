# Mostly for use of CI/CD. Install Pester and run tests.
param (
  # Set to true to remove all Pester versions and install 4.10.1 which supports
  # the way unit tests are written.
  [switch] $CleanPesterAndInstallV4 = $false
)

$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$testDir = Join-Path $parentDir -ChildPath "test"

# Debug info.
$PSVersionTable | Out-String

# List Pester versions.
$pesterVersions = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester" }
$pesterVersions | % { Write-Host $_.Name $_.Version }

if ($pesterVersions.Count -eq 0) {
   Write-Warning "No Pester found, will install Pester 4.10.1"
   $CleanPesterAndInstallV4 = $true
}

if ($CleanPesterAndInstallV4) {
   Remove-Module Pester -Force
   Uninstall-Module Pester -Force -AllVersions
   Install-Module Pester -Force -Scope CurrentUser -RequiredVersion 4.10.1
}

$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}