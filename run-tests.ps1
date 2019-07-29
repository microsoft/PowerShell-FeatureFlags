# Mostly for use of CI/CD. Install Pester and run tests.

# TODO: remove.
# List dependencies before testing. Troubleshooting a build failure on Linux.
Get-ChildItem -Recurse -Path "$PSScriptRoot/External" | ForEach-Object {Write-Host $_.FullName}

Install-Module Pester -Force -Scope CurrentUser
$FailedTests = Invoke-Pester -EnableExit
if ($FailedTests -gt 0) {
    Write-Error "Error: $FailedTests Pester tests failed."
    exit $FailedTests
}