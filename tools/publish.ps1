param(
    [Parameter(Mandatory=$true)]
    [string] $ApiKey,

    [string] $Repository = "PSGallery"
)

$baseDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$buildDir = Join-Path $baseDir -ChildPath "bld\psgallery\FeatureFlags"

Publish-Module -Path $buildDir -NugetApiKey $ApiKey -Verbose -Repository $Repository