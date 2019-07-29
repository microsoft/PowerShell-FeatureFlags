param (
    [switch] $Clean,
    [switch] $List = $false
)
$parentDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$outputDir = Join-Path $parentDir -ChildPath "External"

if ($Clean) {
    Remove-Item -Path $outputDir -Recurse -Force
} else {
    dotnet restore $parentDir --packages $outputDir --force 

    if (-not $?) {
        Write-Error "Could not install packages." -ErrorAction Stop
    }

    if ($List) {
        # List all files for troubleshooting purposes.
        Get-ChildItem -Recurse $outputDir | ForEach-Object { Write-Host $_.FullName }
    }
}