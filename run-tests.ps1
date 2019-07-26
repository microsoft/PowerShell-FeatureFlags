# Mostly for use of CI/CD. Install Pester and run tests.

Install-Module Pester -Force -Scope CurrentUser
$FailedTests = Invoke-Pester -EnableExit
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}