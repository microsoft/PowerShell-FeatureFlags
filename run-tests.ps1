# Mostly for use of CI/CD. Install Pester and run tests.

Install-Module Pester -Force -Scope CurrentUser
Invoke-Pester
