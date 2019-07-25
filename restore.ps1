param (
    [switch] $Clean
)
$outputDir = "External"

if ($Clean) {
    Remove-Item -Path $outputDir -Recurse -Force
} else {
    dotnet restore --packages $outputDir --force 

    if (-not $?) {
        Write-Error "Could not install packages." -ErrorAction Stop
    }
}