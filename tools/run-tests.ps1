# Mostly for use of CI/CD. Install Pester and run tests.
$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Install-Module Pester -Force -Scope CurrentUser
$FailedTests = Invoke-Pester $parentDir -EnableExit
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}