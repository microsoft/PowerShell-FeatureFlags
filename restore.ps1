$outputDir = "External"
nuget install packages.config -ExcludeVersion -NonInteractive -PackageSaveMode nuspec -OutputDirectory $outputDir

if (-not $?) {
    Write-Error "Could not install packages." -ErrorAction Stop
}

# Clean up .nupkg files.
Get-ChildItem -Recurse $outputDir | Where-Object {$_.Extension -ieq ".nupkg"} | Remove-Item