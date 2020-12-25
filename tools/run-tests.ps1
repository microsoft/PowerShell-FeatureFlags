# Mostly for use of CI/CD. Install Pester and run tests.
param (
  # Set to true to remove all Pester versions and install 5.1.0
  # the way unit tests are written.
  [switch] $CleanPesterAndInstallV5 = $false
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
   $CleanPesterAndInstallV5 = $true
}

if ($CleanPesterAndInstallV5) {
   Remove-Module Pester -Force
   Uninstall-Module Pester -Force -AllVersions
   Install-Module Pester -Force -Scope CurrentUser -RequiredVersion 5.1.0
}

$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}