$ErrorActionPreference = "Stop"

$baseDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$buildDir = Join-Path $baseDir -ChildPath "bld\psgallery\FeatureFlags"

if (-not (Test-Path $baseDir/External/newtonsoft.json) -or -not (Test-Path $baseDir/External/njsonschema)) {
    Write-Error "Missing dependencies. Please run restore.ps1."
}

if (Test-Path $buildDir) {
    Write-Host "Cleaning up directory $buildDir"
    Remove-Item $buildDir -Force -Recurse
}

Write-Host "Creating $buildDir and copying everything in there"
$null = New-Item -Path $buildDir -ItemType Directory -Force
$null = New-Item -Path $buildDir/External -ItemType Directory -Force

Copy-Item -Force $baseDir/FeatureFlags.ps?1 $buildDir
Copy-Item -Force $baseDir/featureflags.schema.json $buildDir
Copy-Item -Force $baseDir/LICENSE $buildDir
Copy-Item -Force $baseDir/README.md $buildDir
Copy-Item -Force $baseDir/External/newtonsoft.json $buildDir/External -Recurse
Copy-Item -Force $baseDir/External/njsonschema $buildDir/External -Recurse

$nupkgFiles = Get-ChildItem $buildDir -Recurse | Where-Object {$_.Extension -ieq ".nupkg"}
if ($nupkgFiles.Count -gt 0) {
    Write-Host "Removing $($nupkgFiles.Count) nupkg files: $nupkgFiles"
    $nupkgFiles | ForEach-Object {Remove-Item $_.FullName}
}

Write-Host "List of files (depth == 2):"
Get-ChildItem $buildDir -Depth 2 | ForEach-Object { Write-Host $_.FullName }