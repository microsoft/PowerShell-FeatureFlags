# Mostly for use of CI/CD. Install Pester and run tests.
$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$testDir = Join-Path $parentDir -ChildPath "test"

# Debug info.
$PSVersionTable | Out-String

Write-Host "Checking for Pester > 4.0.0..."
$pester = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester" -and $_.Version -gt '4.0.0'}
if ($pester.Count -eq 0) {
    Write-Host "Cannot find the Pester module. Installing it."
    Install-Module Pester -Force -Scope CurrentUser -RequiredVersion 4.10.1
} else {
    Write-Host "Found Pester version $($pester.Version)."
}

$FailedTests = Invoke-Pester $testDir -EnableExit -OutputFile "test/results.xml" -OutputFormat "NUnitXML" -CodeCoverage "$parentDir/FeatureFlags.psm1"
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}