# Mostly for use of CI/CD. Install Pester and run tests.
$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$testDir = Join-Path $parentDir -ChildPath "test"

$pester = Get-Module -ListAvailable | Where-Object {$_.Name -eq "Pester"}
if ($pester.Count -eq 0) {
    Write-Host "Cannot find the Pester module. Installing it."
    Install-Module Pester -Force -Scope CurrentUser
}
$FailedTests = Invoke-Pester $testDir -EnableExit
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}