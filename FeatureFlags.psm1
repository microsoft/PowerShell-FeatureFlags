$ErrorActionPreference = "Stop"
<#
.SYNOPSIS 
Loads the feature flags configuration from a JSON file.

.DESCRIPTION
This cmdlet reads a JSON file containing feature flag configuration and validates it against 
the feature flags schema. If the configuration is valid, it returns a PowerShell object 
representation of the JSON. If the file is invalid or doesn't exist, it returns $null.

The JSON file should contain two main sections: "stages" for defining rollout stages with 
conditions, and "features" for associating features with stages and environment variables.

.PARAMETER jsonConfigPath
Path to the JSON configuration file.

.OUTPUTS
The output of ConvertFrom-Json (PSCustomObject) if the file contains a valid JSON object
that matches the feature flags JSON schema, $null otherwise.

.EXAMPLE
$config = Get-FeatureFlagConfigFromFile -jsonConfigPath ".\features.json"
if ($config) {
    Write-Host "Configuration loaded successfully"
} else {
    Write-Host "Failed to load configuration"
}

.EXAMPLE
# Load configuration and check available features
$config = Get-FeatureFlagConfigFromFile "C:\config\feature-flags.json"
if ($config -and $config.features) {
    $config.features | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
}
#>
function Get-FeatureFlagConfigFromFile {
    [CmdletBinding()]
    param(
       [string]$jsonConfigPath
    )
    $configJson = Get-Content $jsonConfigPath | Out-String
    if (-not (Confirm-FeatureFlagConfig $configJson)) {
        return $null
    }
    return ConvertFrom-Json $configJson
}

# This library uses Test-Json for JSON schema validation for PowerShell >= 6.1.
# For previous versions, it uses NJsonSchema, which depends on Newtonsoft.JSON.
# Since PowerShell itself uses NJsonSchema and Newtonsoft.JSON, we load these
# assemblies only when it is needed (older PowerShell versions).
$version = $PSVersionTable.PSVersion
Write-Verbose "Running under PowerShell $version"
if ($version -lt [System.Version]"6.1.0") {
    Write-Verbose "Loading JSON/JSON Schema libraries"

    # Get DLLs imported via restore.
    $externalLibs = Get-ChildItem -Recurse -Path "$PSScriptRoot/External"
    $externalLibs = $externalLibs | Where-Object {$_.Extension -ieq ".dll" -and $_.FullName -ilike "*netstandard1.0*"} | ForEach-Object {$_.FullName}

    # If PowerShell ships with Newtonsoft.JSON, let's load that copy rather than the one in the NuGet package.
    $jsonLibPath = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {$_.FullName.StartsWith("Newtonsoft.Json")} | Select-Object -ExpandProperty Location
    if ($null -eq $jsonLibPath) {
        $jsonLibPath = $externalLibs | Where-Object {$_ -ilike "*Newtonsoft.Json.dll"}

        if (-not (Test-Path -Path $jsonLibPath -PathType Leaf)) {
            Write-Error "Could not find the DLL for Newtonsoft.Json: $jsonLibPath"
        }   

        try {
            $jsonType = Add-Type -Path $jsonLibPath -PassThru
            Write-Verbose "JSON.Net type: $jsonType"
        } catch {
            Write-Error "Error loading Newtonsoft.Json libraries ($jsonLibPath): $($_.Exception.Message)"
            throw
        }   
    }
    Write-Verbose "Using Newtonsoft.JSON from $jsonLibPath"

    # Add an assembly redirect in case that NJsonSchema refers to a different version of Newtonsoft.Json.
    Write-Verbose "Adding assembly resolver."
    $onAssemblyResolve = [System.ResolveEventHandler] {
        param($sender, $e)

        if ($e.Name -like 'Newtonsoft.Json, *') {
            Write-Verbose "Resolving '$($e.Name)'"
            return [System.Reflection.Assembly]::LoadFrom($jsonLibPath)
        }

        Write-Verbose "Unable to resolve assembly name '$($e.Name)'"
        return $null
    }
    [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)

    # Load the JSON Schema library.
    $schemaLibPath = $externalLibs | Where-Object {$_ -ilike "*NJsonSchema.dll"}
    if (-not (Test-Path -Path $schemaLibPath -PathType Leaf)) {
        Write-Error "Could not find the DLL for NJSonSchema: $schemaLibPath"
    }
    Write-Verbose "Found NJsonSchema assembly at $schemaLibPath"

    try {
        $jsonSchemaType = Add-Type -Path $schemaLibPath -PassThru
        Write-Verbose "NjsonSchema type: $jsonSchemaType"
    } catch {
        Write-Error "Error loading JSON schema library ($schemaLibPath): $($_.Exception.Message)"
        throw
    }

    # Unregister the assembly resolver.
    Write-Verbose "Removing assemlby resolver."
    [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
}

try {
    Write-Verbose "Reading JSON schema..."
    $script:schemaContents = Get-Content $PSScriptRoot\featureflags.schema.json -Raw
} catch {
    Write-Error "Error reading JSON schema: $($_.Exception.Message)"
    throw
}

if ($version -lt [System.Version]"6.1.0") {
    try {
        Write-Verbose "Loading JSON schema..."
        $script:schema = [NJsonSchema.JSonSchema]::FromJsonAsync($script:schemaContents).GetAwaiter().GetResult()
    } catch {
        $firstException = $_.Exception
        # As a fallback, try reading using the JsonSchema4 object. The JSON schema library
        # exposes that object to .NET Framework instead of JsonSchema for some reason.
        try {
            Write-Verbose "Loading JSON schema (fallback)..."
            $script:schema = [NJsonSchema.JSonSchema4]::FromJsonAsync($script:schemaContents).GetAwaiter().GetResult()
        } catch {
            Write-Error "Error loading JSON schema: $($_.Exception.Message). First error: $($firstException.Message)."
            Write-Host $_.Exception.Message
            throw
        }
    }
    Write-Verbose "Loaded JSON schema from featureflags.schema.json."
    Write-Verbose $script:schema
}

<#
.SYNOPSIS 
Validates feature flag configuration.

.DESCRIPTION
This cmdlet validates a feature flag configuration JSON string against the feature flags 
schema. It performs both JSON schema validation and additional business logic validation,
such as ensuring that all features reference defined stages.

The validation includes checking that the JSON structure matches the expected schema for
stages and features, and that all stage references in features actually exist in the
stages section.

.PARAMETER serializedJson
String containing a JSON object.

.OUTPUTS
$true if the configuration is valid, false if it's not valid or if the config schema
could not be loaded.

.EXAMPLE
$jsonConfig = Get-Content "features.json" -Raw
if (Confirm-FeatureFlagConfig -serializedJson $jsonConfig) {
    Write-Host "Configuration is valid"
} else {
    Write-Host "Configuration validation failed"
}

.EXAMPLE
# Validate a simple configuration
$simpleConfig = @"
{
  "stages": {
    "test": [{"allowlist": ["test.*"]}]
  },
  "features": {
    "new-feature": {"stages": ["test"]}
  }
}
"@
Confirm-FeatureFlagConfig -serializedJson $simpleConfig

.NOTES
The function accepts null/empty configuration because it's preferable to just return
$false in case of such invalid configuration rather than throwing exceptions that need
to be handled.
#>
function Confirm-FeatureFlagConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $serializedJson
    )

    if ($version -lt [System.Version]"6.1.0" -and $null -eq $script:schema) {
        Write-Error "Couldn't load the schema, considering the configuration as invalid."
        return $false
    }
    if ($null -eq $serializedJson -or $serializedJson.Length -eq 0) {
        Write-Error "Cannot validate the configuration, since it's null or zero-length."
        return $false
    }
    try {

        if ($version -lt [System.Version]"6.1.0") {
            $errors = $script:schema.Validate($serializedJson)
        } else {
            $res = Test-Json -Json $serializedJson -Schema $script:schemaContents
            if (-not $res) {
                $errors = "Exception during validation"
            }
        }
        if ($null -eq $errors -or ($errors.Count -eq 0)) {
            if(-not (Confirm-StagesPointers $serializedJson)) {
                return $false
            }
            return $true
        }
        $message = -join $errors
        Write-Error "Validation failed. Error details:`n ${message}"
        return $false
    } catch {
        Write-Error "Exception when validating. Exception: $_"
        return $false
    }
}

# Checks whether all features in the given feature flags configuration
# point to stages that have been defined in the configuration itself.
#
# Unfortunately it's impossible to express this concept with the current
# JSON schema standard.
function Confirm-StagesPointers {
    [CmdletBinding()]   
    param(
        [string] $serializedJson
    )

    $config = ConvertFrom-Json $serializedJson
    if ($null -eq $config.features) {
        return $true
    }

    # Using the dictionary data structure as a set (values are ignored).
    $stageNames = @{}
    $config.stages | get-member -Membertype NoteProperty | Foreach-Object {$stageNames.Add($_.Name, "")}

    $featureStages = @($config.features | get-member -MemberType NoteProperty | Foreach-Object {$config.features.($_.Name)})

    foreach($stage in $featureStages.stages) {
        if (-not ($stageNames.ContainsKey($stage))) {
            Write-Error "Stage ${stage} is used in the features configuration but is never defined."
            return $false
        }
    }

    return $true
}

# Checks whether $predicate matches any of the regular expressions in $regexList.
function Test-RegexList {
    param(
        [string] $predicate,
        [string[]] $regexList
    )
    foreach ($regex in $regexList) {
        Write-Verbose "Checking regex $regex"
        if ($predicate -match $regex) {
            return $true
        }
    }
    Write-Verbose "The predicate $predicate does not match any regex in the list of regular expressions"
    return $false
}

<#
.SYNOPSIS 
Tests if a given feature is enabled by testing a predicate against the given feature flag configuration.

.DESCRIPTION
This cmdlet evaluates whether a specific feature should be enabled for a given predicate by 
checking the feature's associated stages and their conditions. The predicate is typically 
an identifier (like a machine name, user ID, or environment name) that gets tested against 
the stage conditions.

Each feature can be associated with multiple stages, and the feature is considered enabled 
if ANY of its stages evaluate to true. Stages contain conditions (allowlist, denylist, 
probability) that are evaluated in order, and ALL conditions in a stage must be satisfied 
for that stage to be considered active.

.PARAMETER featureName
The name of the feature to test.

.PARAMETER predicate
The predicate to use to test if the feature is enabled.

.PARAMETER config
A feature flag configuration, which should be parsed and checked by Get-FeatureFlagConfigFromFile.

.OUTPUTS
$true if the feature flag is enabled, $false if it's not enabled or if any other errors happened during
the verification.

.EXAMPLE
$config = Get-FeatureFlagConfigFromFile -jsonConfigPath "features.json"
$isEnabled = Test-FeatureFlag -featureName "new-ui" -predicate "prod-server1" -config $config
if ($isEnabled) {
    Write-Host "New UI feature is enabled for prod-server1"
}

.EXAMPLE
# Test multiple predicates for a feature
$config = Get-FeatureFlagConfigFromFile "features.json"
$predicates = @("test-env", "dev-machine", "prod-canary")
foreach ($predicate in $predicates) {
    $result = Test-FeatureFlag -featureName "experimental-feature" -predicate $predicate -config $config
    Write-Host "${predicate}: $result"
}

.EXAMPLE
# Test feature enablement and set environment variables accordingly
$config = Get-FeatureFlagConfigFromFile "features.json"
if (Test-FeatureFlag -featureName "new-cache" -predicate $env:COMPUTERNAME -config $config) {
    $env:USE_NEW_CACHE = "1"
    Write-Host "New cache feature enabled"
}
#>
function Test-FeatureFlag {
    [CmdletBinding()]
    param (
        [string] $featureName,
        [string] $predicate,
        [PSCustomObject] $config
    )
    try {
        $stages = $config.features.($featureName).stages
        if ($stages.Count -eq 0) {
            Write-Verbose "The feature ${featureName} is not in the configuration."
            return $false
        }
        $result = $false
        foreach ($stageName in $stages)
        {
            $conditions = $config.stages.($stageName)
            $featureResult = Test-FeatureConditions -conditions $conditions -predicate $predicate -config $config
            $result = $result -or $featureResult
        }
        return $result
    } catch {
        Write-Error "Exception when evaluating the feature flag ${featureName}. Considering the flag disabled. Exception: $_"
        return $false
    }
}

function Test-FeatureConditions
{
    [CmdletBinding()]
    param(
        [PSCustomObject] $conditions,
        [string] $predicate,
        [PSCustomObject] $config
    )
    # Conditions are evaluated in the order they are presented in the configuration file.
    foreach ($condition in $conditions) {
        # Each condition object can have only one of the allowlist, denylist or probability
        # attributes set. This invariant is enforced by the JSON schema, which uses the "oneof"
        # strategy to choose between allowlist, denylist or probability and, for each of these
        # condition types, only allows the homonym attribute to be set.
        if ($null -ne $condition.allowlist) {
            Write-Verbose "Checking the allowlist condition"
            # The predicate must match any of the regexes in the allowlist in order to
            # consider the allowlist condition satisfied.
            $matchesallowlist = Test-RegexList $predicate @($condition.allowlist)
            if (-not $matchesallowlist) {
                return $false
            }
        } elseif ($null -ne $condition.denylist) {
            Write-Verbose "Checking the denylist condition"
            # The predicate must not match all of the regexes in the denylist in order to
            # consider the denylist condition satisfied.
            $matchesdenylist = Test-RegexList $predicate @($condition.denylist)
            if ($matchesdenylist) {
                return $false
            }
        } elseif ($null -ne $condition.probability) {
            Write-Verbose "Checking the probability condition"
            $probability = $condition.probability
            $random = (Get-Random) % 100 / 100.0
            Write-Verbose "random: ${random}. Checking against ${probability}"
            if($random -ge $condition.probability)
            {
                Write-Verbose "Probability condition not met: ${random} ≥ ${probability}"
                return $false
            }
        } else {
            throw "${condition} is not a supported condition type (denylist, allowlist or probability)."
        }
    }
    return $true
}

<#
.SYNOPSIS
Returns the list of supported features by name

.PARAMETER config
A feature flag configuration

.OUTPUTS
Array of the supported features by name.
#>
function Get-SupportedFeatures
{
    [CmdletBinding()]
    param(
        [PSCustomObject] $config
    )

    if($null -eq $config.features -or $config.features.Count -eq 0)
    {
        $featureNames = @()
    }
    else 
    {
        $featureNames = @($config.features | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name })
    }

    Write-Output $featureNames
}

<#
.SYNOPSIS
Parses the feature flags config for the environment variables collection associated to a specific feature

.PARAMETER Config
A feature flag configuration

.OUTPUTS
Returns the environment variables collection associated with a specific feature
#>
function Get-FeatureEnvironmentVariables
{
    [CmdletBinding()]
    param(
        [PSCustomObject] $Config,
        [string] $FeatureName
    )
    $featureEnvironmentVariables = $Config.features.($FeatureName).environmentVariables

    Write-Output $featureEnvironmentVariables
}

<#
.SYNOPSIS
Determines the enabled features from the specified feature config using the provided predicate.

.DESCRIPTION
This cmdlet evaluates all features defined in the configuration against a given predicate 
and returns a hashtable showing which features are enabled or disabled. This is useful 
for getting a complete picture of feature enablement for a specific context (like a 
particular server, user, or environment).

The returned hashtable contains feature names as keys and boolean values indicating 
whether each feature is enabled (True) or disabled (False) for the given predicate.

.PARAMETER predicate
The predicate to use to test if the feature is enabled.

.PARAMETER config
Feature flag configuration object

.OUTPUTS
Returns a hashtable of the evaluated feature flags given the specified predicate.

.EXAMPLE
$config = Get-FeatureFlagConfigFromFile -jsonConfigPath "features.json"
$results = Get-EvaluatedFeatureFlags -predicate "prod-server1" -config $config
$results.GetEnumerator() | ForEach-Object {
    Write-Host "Feature '$($_.Key)': $($_.Value)"
}

.EXAMPLE
# Get enabled features for current machine
$config = Get-FeatureFlagConfigFromFile "features.json"
$enabledFeatures = Get-EvaluatedFeatureFlags -predicate $env:COMPUTERNAME -config $config
$enabledFeatures.GetEnumerator() | Where-Object { $_.Value -eq $true } | ForEach-Object {
    Write-Host "Enabled: $($_.Key)"
}

.EXAMPLE
# Compare feature enablement across environments
$config = Get-FeatureFlagConfigFromFile "features.json"
$environments = @("test-env", "staging-env", "prod-env")
foreach ($env in $environments) {
    Write-Host "Environment: $env"
    $features = Get-EvaluatedFeatureFlags -predicate $env -config $config
    $features.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
}
#>
function Get-EvaluatedFeatureFlags
{
    [CmdletBinding()]
    param(
        [string] $predicate,
        [PSCustomObject] $config
    )

    $allFeaturesList = Get-SupportedFeatures -config $config

    $evaluatedFeatures = @{}

    foreach($featureName in $allFeaturesList)
    {
        $isEnabled = Test-FeatureFlag -featureName $featureName -predicate $predicate -config $config
        $evaluatedFeatures.Add($featureName, $isEnabled)
    }

    Write-Output $evaluatedFeatures
}

<#
.SYNOPSIS
Writes the evaluated features to a file in the specified output folder

.DESCRIPTION
This cmdlet takes a collection of evaluated feature flags and writes them to multiple file 
formats in the specified output folder. It creates three types of files:

1. JSON file (.json) - Contains the feature flags in JSON format
2. INI file (.ini) - Contains the feature flags in INI/key-value format  
3. Environment config file (.env.config) - Contains environment variables for enabled features

The environment config file only includes features that are enabled and have associated 
environment variables defined in the configuration. This is useful for setting up 
environment-specific configurations in deployment scenarios.

.PARAMETER Config
Feature flag configuration object

.PARAMETER EvaluatedFeatures
The collection of evaluated features

.PARAMETER OutputFolder
The folder to write the evaluated features file

.PARAMETER FileName
The prefix filename to be used when writing out the features files

.OUTPUTS
Outputs multiple file formats expressing the evaluated feature flags

.EXAMPLE
$config = Get-FeatureFlagConfigFromFile -jsonConfigPath "features.json"
$evaluated = Get-EvaluatedFeatureFlags -predicate "prod-server1" -config $config
Out-EvaluatedFeaturesFiles -Config $config -EvaluatedFeatures $evaluated -OutputFolder "C:\output"

# This creates:
# C:\output\features.json
# C:\output\features.ini  
# C:\output\features.env.config

.EXAMPLE
# Generate feature files for multiple environments
$config = Get-FeatureFlagConfigFromFile "features.json"
$environments = @("dev", "staging", "prod")
foreach ($env in $environments) {
    $evaluated = Get-EvaluatedFeatureFlags -predicate $env -config $config
    Out-EvaluatedFeaturesFiles -Config $config -EvaluatedFeatures $evaluated -OutputFolder ".\output\$env" -FileName "features-$env"
}

.EXAMPLE
# Custom filename for output files
$config = Get-FeatureFlagConfigFromFile "features.json"
$evaluated = Get-EvaluatedFeatureFlags -predicate $env:COMPUTERNAME -config $config
Out-EvaluatedFeaturesFiles -Config $config -EvaluatedFeatures $evaluated -OutputFolder ".\deployment" -FileName "machine-features"

.NOTES
The output directory will be created automatically if it doesn't exist. Environment 
variables are only written to the .env.config file for features that are both enabled 
and have environmentVariables defined in the configuration.
#>
function Out-EvaluatedFeaturesFiles
{
    [CmdletBinding()]
    param(
        [PSCustomObject] $Config,
        [PSCustomObject] $EvaluatedFeatures,
        [string] $OutputFolder,
        [string] $FileName = "features"
    )
    if($null -eq $EvaluatedFeatures)
    {
        throw "EvaluatedFeatures input cannot be null."
    }
    if(-not (Test-Path $outputFolder))
    {
        $null = New-Item -ItemType Directory -Path $outputFolder
    }
    Out-FeaturesJson -EvaluatedFeatures $EvaluatedFeatures -OutputFolder $OutputFolder -FileName $FileName
    Out-FeaturesIni -EvaluatedFeatures $EvaluatedFeatures -OutputFolder $OutputFolder -FileName $FileName
    Out-FeaturesEnvConfig -Config $Config -EvaluatedFeatures $EvaluatedFeatures -OutputFolder $OutputFolder -FileName $FileName
}

function Out-FeaturesJson
{
    param(
        [PSCustomObject] $EvaluatedFeatures,
        [string] $OutputFolder,
        [string] $FileName
    )
    $featuresJson = Join-Path $outputFolder "${FileName}.json"
    $outJson = $EvaluatedFeatures | ConvertTo-Json -Depth 5 
    $outJson | Out-File -Force -FilePath $featuresJson
}

function Out-FeaturesIni
{
    param(
        [PSCustomObject] $EvaluatedFeatures,
        [string] $OutputFolder,
        [string] $FileName
    )
    $featuresIni = Join-Path $OutputFolder "${FileName}.ini"
    if(Test-Path $featuresIni)
    {
        $null = Remove-Item -Path $featuresIni -Force
    }
    $EvaluatedFeatures.Keys | ForEach-Object { Add-Content -Value "$_`t$($evaluatedFeatures[$_])" -Path $featuresIni }
}

function Out-FeaturesEnvConfig
{
    param(
        [PSCustomObject] $Config,
        [PSCustomObject] $EvaluatedFeatures,
        [string] $OutputFolder,
        [string] $FileName
    )
    $featuresEnvConfig = Join-Path $OutputFolder "${FileName}.env.config"
    if(Test-Path $featuresEnvConfig)
    {
        $null = Remove-Item -Path $featuresEnvConfig -Force
    }

    $EvaluatedFeatures.Keys | Where-Object { $EvaluatedFeatures[$_] -eq $true } | ForEach-Object {
        $envVars = Get-FeatureEnvironmentVariables -Config $Config -FeatureName $_
        if($envVars)
        {
            Add-Content -Value "# Feature [$_] Environment Variables" -Path $featuresEnvConfig
            foreach($var in $envVars)
            {
                $name = ($var | Get-Member -MemberType NoteProperty).Name
                Add-Content -Value "$name`t$($var.$name)" -Path $featuresEnvConfig
            }
        }
    }
}
