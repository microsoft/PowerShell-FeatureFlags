<#
.SYNOPSIS 
Loads the feature flags configuration from a JSON file.

.PARAMETER jsonConfigPath
Path to the JSON file containing the configuration.

.OUTPUTS
The output of ConvertFrom-Json (PSCustomObject) if the file contains a valid JSON object
that matches the feature flags JSON schema, $null otherwise.
#>
function Get-FeatureFlagConfigFromFile([string]$jsonConfigPath) {
    $configJson = Get-Content $jsonConfigPath | Out-String
    if (-not (Confirm-FeatureFlagConfig $configJson)) {
        return $null
    }
    return ConvertFrom-Json $configJson
}

# This library uses Test-Json for JSON schema validation for PowerShell >= 6.1.
# For previous versions, it uses NJsonSchema, # which depends on Newtonsoft.JSON.
# Since PowerShell itself uses NJsonSchema and Newtonsoft.JSON, we load these
# assemblies only when it is needed (older PowerShell versions).
$version = $PSVersionTable.PSVersion
Write-Verbose "Running under PowerShell $version"
if ($version -lt [System.Version]"6.1.0") {
    Write-Verbose "Loading JSON/JSON Schema libraries"
    # Import the JSON and JSON schema libraries, and load the JSON schema.
    $libs = Get-ChildItem -Recurse -Path "$PSScriptRoot/External"
    $libs = $libs | Where-Object {$_.Extension -ieq ".dll" -and $_.FullName -ilike "*netstandard1.0*"} | ForEach-Object {$_.FullName}
    $schemaLibPath = $libs | Where-Object {$_ -ilike "*NJsonSchema.dll"}
    if (-not (Test-Path -Path $schemaLibPath -PathType Leaf)) {
        Write-Error "Could not find the DLL for NJSonSchema: $schemaLibPath"
    }
    Write-Verbose "Found NJsonSchema assembly at $schemaLibPath"

    $jsonLibPath = $libs | Where-Object {$_ -ilike "*Newtonsoft.Json.dll"}
    if (-not (Test-Path -Path $jsonLibPath -PathType Leaf)) {
        Write-Error "Could not find the DLL for Newtonsoft.Json: $jsonLibPath"
    }
    Write-Verbose "Found JSON.Net assembly at $jsonLibPath"

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

    try {
        $jsonType = Add-Type -Path $jsonLibPath -PassThru
        $jsonSchemaType = Add-Type -Path $schemaLibPath -PassThru
        #Write-Verbose "JSON.Net type: $jsonType"
        #Write-Verbose "NjsonSchema type: $jsonSchemaType"
    } catch {
        Write-Error "Error loading JSON libraries ($jsonLibPath, $schemaLibPath): $($_.Exception.Message)"
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

.PARAMETER serializedJson
String containing a JSON object.

.OUTPUTS
$true if the configuration is valid, false if it's not valid or if the config schema
could not be loaded.

.NOTES
The function accepts null/empty configuration because it's preferable to just return
$false in case of such invalid configuration rather than throwing exceptions that need
to be handled.
#>
function Confirm-FeatureFlagConfig {
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

.PARAMETER featureName
The name of the feature to test.

.PARAMETER predicate
The predicate to use to test if the feature is enabled.

.PARAMETER config
A feature flag configuration, which should be parsed and checked by Get-FeatureFlagConfigFromFile.

.OUTPUTS
$true if the feature flag is enabled, $false if it's not enabled or if any other errors happened during
the verification.
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

.PARAMETER predicate
The predicate to use to test if the feature is enabled.

.PARAMETER config
Feature flag configuration object

.OUTPUTS
Returns an array of the evaluated feature flags given the specified predicate.
#>
function Get-EvaluatedFeatureFlags
{
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
#>
function Out-EvaluatedFeaturesFiles
{
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