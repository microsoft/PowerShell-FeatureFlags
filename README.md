[![Nuget](https://img.shields.io/nuget/v/FeatureFlags.PowerShell)](https://www.nuget.org/packages/FeatureFlags.PowerShell/1.0.0)
[![Platforms](https://img.shields.io/powershellgallery/p/FeatureFlags.svg)](https://www.powershellgallery.com/packages/FeatureFlags/)
[![FeatureFlags](https://img.shields.io/powershellgallery/v/FeatureFlags.svg)](https://www.powershellgallery.com/packages/FeatureFlags/)


# PowerShell Feature Flags

This package contains a simple, low-dependencies implementation of feature
flags for PowerShell, which relies on a local configuration file to verify if
a given feature should be enabled or not.

The configuration file contains two sections:
- **stages**: a section where roll-out stages are defined;
- **features**: a section where each feature can be associated to a roll-out stage.

A roll-out *stage* is defined by a name and an array of *conditions* that the
predicate must match **in the order they are presented** for the feature associated to
the given stage to be enabled.

Stage names and feature names must be non-empty and must consist of non-space characters.

A feature can be assigned an array of stages that it applies to. In addition,
it can also accept an environment variable array, and can optionally output
an environment configuration file.

For more general information about feature flags, please visit [featureflags.io](https://featureflags.io).

## Installation

This module is available from the PowerShell Gallery. Therefore, to install it for all users
on the machine type the following from an administrator PowerShell prompt:

```powershell
PS > Install-Module FeatureFlags
```

To install as an unprivileged user, type the following from any PowerShell prompt:

```powershell
PS > Install-Module FeatureFlags -Scope CurrentUser
```

## Simple example

Imagine to have a feature flag configuration file called `features.json`:

```js
{
  "stages": {
    "test": [
      {"allowlist": ["test.*", "dev.*"]}
    ],
    "canary": [
      {"allowlist": ["prod-canary"]}
    ],
    "prod": [
      {"allowlist": ["prod.*"]},
      {"denylist": ["prod-canary"]}
    ]
  },
  "features": {
    "experimental-feature": {
      "stages": ["test"]
    },
    "well-tested-feature": {
      "stages": ["test", "canary", "prod"]
    }
  }
}
```

This file defines 3 stages: `test`, `canary` and `prod`, and 2 features: `experimental-feature` and `well-tested-feature`.

The intent of the configuration is to enable `experimental-feature` in `test` only (all predicates starting with `test` or `dev`),
and to enable `well-tested-feature` in all stages.

Let's first read the configuration:

```powershell
$cfg = Get-FeatureFlagConfigFromFile features.json
```

This step would fail if there is any I/O error (e.g., file doesn't exist), if the file is not valid JSON or if the file does not conform with the [feature flags schema](featureflags.schema.json).

Let's now test a couple of predicates to verify that the configuration does what we expect:

```powershell
PS > Test-FeatureFlag -config $cfg -Feature "well-tested-feature" -predicate "test1"
True 
PS > Test-FeatureFlag -config $cfg -Feature "well-tested-feature" -predicate "test2"
True 
PS > Test-FeatureFlag -config $cfg -Feature "well-tested-feature" -predicate "dev1" 
True                                                                                                                                
PS > Test-FeatureFlag -config $cfg -Feature "well-tested-feature" -predicate "prod-canary1"
True 
PS > Test-FeatureFlag -config $cfg -Feature "experimental-feature" -predicate "prod-canary1"
False 
PS > Test-FeatureFlag -config $cfg -Feature "experimental-feature" -predicate "test1"
True 
PS > Test-FeatureFlag -config $cfg -Feature "experimental-feature" -predicate "prod1"
False 
```

For more complex examples, please look at test cases. More examples will be added in the future (Issue #6).

## Life of a feature flag

Feature flags are expected to be in use while a feature is rolled out to production,
or in case there is a need to conditionally enable or disable features.

An example lifecycle of a feature flag might be the following:

1. A new feature is checked in production after testing, in a disabled state;
2. The feature is enabled for a particular customer;
3. The feature is enabled for a small set of customers;
4. The feature is gradually rolled out to increasingly large percentages of customers
   (e.g., 5%, 10%, 30%, 50%)
5. The feature is rolled out to all customers (100%)
6. The test for the feature flag is removed from the code, and the feature flag
   configuration is removed as well.

Here is how these example stages could be implemented:

* Stage 1 can be implemented with a `denylist` condition with value `.*`.
* Stages 2 and 3 can be implemented with `allowlist` conditions.
* Stages 4 and 5 can be implemented with `probability` conditions.

## Conditions

There are two types of conditions: *deterministic* (allowlist and denylist,
regex-based) and *probabilistic* (probability, expressed as a number between
0 and 1). Conditions can be repeated if multiple instances are required.

All conditions in each stage must be satisfied, in the order they are listed
in the configuration file, for the feature to be considered enabled.

If any condition is not met, evaluation of conditions stops and the feature
is considered disabled.

### Allow list

The `allowlist` condition allows to specify a list of regular expressions; if the
predicate matches any of the expressions, then the condition is met and the evaluation
moves to the next condition, if there is any.

The regular expression is not anchored. This means that a regex of `"storage"` will
match both the predicate `"storage"` and the predicate `"storage1"`. To prevent
unintended matches, it's recommended to always anchor the regex.

So, for example, `"^storage$"` will only match `"storage"` and not `"storage1"`.

### Deny list

The `denylist` condition is analogous to the allowlist condition, except that if
the predicate matches any of the expressions the condition is considered not met
and the evaluation stops.

### Probability

The `probability` condition allows the user to specify a percentage of invocations
that will lead to the condition to be met, expressed as a floating point number
between 0 and 1.

So, if the user specifies a value of `0.3`, roughly 30% of times the condition is
checked it will be considered met, while for the remaining 70% of times
it will be considered unmet.

The position of the `probability` condition is very important. Let's look at
the following example:

```json
{
    "stages": {
        "allowlist-first": [
            {"allowlist": ["storage.*"]},
            {"probability": 0.1}
        ],
        "probability-first": [
            {"probability": 0.1}
            {"allowlist": ["storage.*"]},
        ]
    }
}
```

The first stage definition, `allowlist-first`, will evaluate the `probability` condition
only if the predicate first passes the allowlist.

The second stage definition, `probability-first`, will instead first evaluate
the `probability` condition, and then apply the allowlist.

Assuming there are predicates that do not match the allowlist, the second stage definition
is more restrictive than the first one, leading to fewer positive evaluations of the
feature flag.

## Cmdlets

This package provides five PowerShell cmdlets:

* `Test-FeatureFlag`, which checks if a given feature is enabled by testing a predicate
  against the given feature flag configuration;
* `Confirm-FeatureFlagConfig`, which validates the given feature flag configuration by
  first validating it against the feature flags JSON schema and then by applying some
  further validation rules;
* `Get-FeatureFlagConfigFromFile`, which parses and validates a feature flag configuration
  from a given file.
* `Get-EvaluatedFeatureFlags`, which can be used to determine the collection of feature flags,
  from the feature flags config, that apply given the specified predicate.
* `Out-EvaluatedFeaturesFiles`, which will write out feature flag files (.json, .ini, env.config)
  which will indicate which features are enabled, and which environment variables should be set.

## A more complex example

**NOTE**: comments are added in-line in this example, but the JSON format does not allow
for comments. Don't add comments to your feature flag configuration file.

```js
{
  // Definition of roll-out stages.
  "stages": {
    // Examples of probabilistic stages.
    "1percent": [
      {"probability": 0.01},
    ],
    "10percent": [
      {"probability": 0.1},
    ],
    "all": [
      {"probability": 1},
    ],
    // Examples of deterministic stages.
    "all-storage": [
      {"allowlist": [".*Storage.*"]},
    ],
    "storage-except-important": [
      {"allowlist": [".*Storage.*"]},
      {"denylist": [".*StorageImportant.*"]},
    ],
    // Example of mixed roll-out stage.
    // This stage will match on predicates containing the word "Storage"
    // but not the word "StorageImportant", and then will consider the feature
    // enabled in 50% of the cases.
    "50-percent-storage-except-StorageImportant": [
      {"allowlist": [".*Storage.*"]},
      {"denylist": ["StorageImportant"]},
      {"probability": 0.5},
    ],
  },
  // Roll out status of different features:
  "features": {
    "msbuild-cache": {
      "stages": ["all-storage"],
      "environmentVariables": [
        { "Use_MsBuildCache": "1" }
      ]
    },
    "experimental-feature": {
      "stages": ["1percent"]
      // Environment Variables are optional
    },
    "well-tested-feature": {
      "stages": ["all"],
      "environmentVariables": [
        { "Use_TestedFeature": "1" }
      ]
    },
  }
}
```

## Why JSON?

The configuration file uses JSON, despite its shortcomings, for the following
reasons:

1. it's supported natively by PowerShell, therefore it makes this package free
   from dependencies;
2. it's familiar to most PowerShell developers.

Other formats, such as Protocol Buffers, while being technically superior,
have been excluded for the above reasons.

## Relationship to similar projects

There are some projects that allow to use Feature Flags in PowerShell:

* **[microsoft/featurebits](https://github.com/microsoft/featurebits)**: this package uses a SQL database
  to store feature flags value. While the features provided by this project are similar, our
  `FeatureFlags` package does not need any external dependency to run, as features are stored in
  a local file.

* **SaaS (Software-as-a-Service) solutions**: using an external service for feature flags has its pros
  and cons. They typically are much easier to manage and offer rich interfaces to manage the flags;
  however, the specific use case for which this library was born is to enable feature flags for
  PowerShell code which might not be able to open network connections: this requires the library and
  the feature flags definition to be co-located with the code (hermeticity).

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
