<#
    .SYNOPSIS Tests for the FeatureFlags module.
    .NOTES Please update to the last version of Pester before running the tests:
           https://github.com/pester/Pester/wiki/Installation-and-Update.
           After updating, run the Invoke-Pester cmdlet from the project directory.
#>

$ModuleName = "FeatureFlags"
Import-Module $PSScriptRoot\..\${ModuleName}.psd1 -Force
Import-Module $PSScriptRoot\test-functions.psm1

Describe 'Confirm-FeatureFlagConfig' {
    Context 'Validation of invalid configuration' {
        It 'Fails on empty or null configuration' {
            Confirm-FeatureFlagConfig -EA 0 "{}" | Should -Be $false
            Confirm-FeatureFlagConfig -EA 0 $null | Should -Be $false
        }

        It 'Fails on configuration that is not well-formed JSON' {
            Confirm-FeatureFlagConfig '{"stages": "}' -EA 0 | Should -Be $false
        }

        It 'Fails on well-formed configuration not matching the schema' {
            # Missing "stages".
            Confirm-FeatureFlagConfig -EA 0 '{"key": "x"}' | Should -Be $False
            Confirm-FeatureFlagConfig -EA 0 '{"features": {}}' | Should -Be $False

            # Wrong type for "stages".
            Confirm-FeatureFlagConfig -EA 0 '{"stages": "x"}' | Should -Be $False

            # Extra field "foo".
            Confirm-FeatureFlagConfig -EA 0 '{"stages": {}, "foo": ""}' | Should -Be $false
        }

        It 'Fails if a stage is not an array' {
            Confirm-FeatureFlagConfig -EA 0 '{"stages": {"foo": 1}}' | Should -Be $false
            Confirm-FeatureFlagConfig -EA 0 '{"stages": {"bar": [1, 2], "foo": 1}}' | Should -Be $false
        }

        It 'Fails if a stage maps to an empty list of conditions' {
            Confirm-FeatureFlagConfig -EA 0 '{"stages": {"foo": []}}' | Should -Be $false
        }
    }

    Context 'Error output' {
        It 'Outputs correct error messages in case of failure' {
            # Write-Error will add errors to the $error variable and output them to standard error.
            # When run with -EA 0 (ErrorAction SilentlyContinue), the errors will be added to $error
            # but not printed to stderr, which is desirable to not litter the unit tests output.
            Confirm-FeatureFlagConfig -EA 0 $null | Should -Be $false
            $error[0] | Should -BeLike "*null or zero-length*"

            Confirm-FeatureFlagConfig -EA 0 "{}" | Should -Be $false
            $error[0] | Should -BeLike "*Validation failed*"

            Confirm-FeatureFlagConfig -EA 0 '{"stages": {"foo": []}}' | Should -Be $false
            $error[0] | Should -BeLike "*Validation failed*"

            Confirm-FeatureFlagConfig '{"stages": "}' -EA 0 | Should -Be $false
            $error[0] | Should -BeLike "*Exception*"
            $error[0] | Should -BeLike "*unterminated*"
        }
    }

    Context 'Validation of configs with typos in sections or properties' {
        It 'Fails if "stages" is misspelled' {
            $cfg = @"
            {
                "stags": {
                    "storage": [
                        {"whitelist": [".*storage.*"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
        }

        It 'Fails if a condition name contains a typo (whtelist)' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whtelist": [".*storage.*"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
        }

        It 'Fails if "features" is misspelled' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whitelist": [".*storage.*"]}
                    ]
                },
                "featurs": {
                    "foo": "storage"
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
        }

        It 'Fails if the stage name is an empty string' {
            $cfg = @"
            {
                "stages": {
                    "": [
                        {"whitelist": [".*storage.*"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
        }

        It 'Fails if the stage name is a string containing only spaces' {
            $cfg = @"
            {
                "stages": {
                    "    ": [
                        {"whitelist": [".*storage.*"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
        }
    }

    Context 'Successful validation of simple stages' {
        It 'Succeeds with a simple stage with two whitelists' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whitelist": [".*storage.*", ".*compute.*"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig $cfg | Should -Be $true
        }

        It 'Succeeds with a simple stage with a whitelist and a blacklist' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whitelist": [".*storage.*"]}, 
                        {"blacklist": ["ImportantStorage"]}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig $cfg | Should -Be $true
        }
        It 'Succeeds with a simple stage with a probability condition' {
            $cfg = @"
            {
                "stages": {
                    "1percent": [
                        {"probability": 0.1}
                    ]
                }
            }
"@
            Confirm-FeatureFlagConfig $cfg | Should -Be $true
        }
    }

    Context 'Successful validation of stages and features' {
        It 'Succeeds validating a very simple config file with one feature and one stage' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whitelist": [".*storage.*"]}
                    ]
                },
                "features": {
                    "foo": {
                        "stages": ["storage"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $true
        }

        It 'Succeeds validating a very simple config file with two features and two stages' {
            $cfg = @"
            {
                "stages": {
                    "all": [
                        {"whitelist": [".*"]}
                    ], 
                    "storage": [
                        {"whitelist": [".*storage.*"]}
                    ]
                },
                "features": {
                    "foo": {
                        "stages": ["storage"]
                    },
                    "bar": {
                        "stages": ["all"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $true
        }
    }

    Context 'Validation of configs with features pointing to non-existent stages' {
        It 'Fails validation when a feature points to a non-existing stage' {
            $cfg = @"
            {
                "stages": {
                    "storage": [
                        {"whitelist": [".*storage.*"]}
                    ]
                },
                "features": {
                    "foo": {
                        "stages": ["all"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig -EA 0 $cfg | Should -Be $false
            $error[0] | Should -Be "Stage all is used in the features configuration but is never defined."
        }
    }
}

Describe 'Get-FeatureFlagConfigFromFile' {
    It 'Succeeds to load valid configuration files from a file' {
        Get-FeatureFlagConfigFromFile "$PSScriptRoot\multiple-stages.json" | Should -Not -Be $null
        Get-FeatureFlagConfigFromFile "$PSScriptRoot\single-stage.json" | Should -Not -Be $null
    }
}

Describe 'Test-FeatureFlag' {
    Context 'Whitelist condition' {
        Context 'Simple whitelist configuration' {
            $serializedConfig = @"
            {
                "stages": {
                    "all": [
                        {"whitelist": [".*"]}
                    ]
                },
                "features": {
                    "well-tested": {
                        "stages": ["all"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig $serializedConfig
            $config = ConvertFrom-Json $serializedConfig

            It 'Rejects non-existing features' {
                Test-FeatureFlag "feature1" "Storage/master" $config | Should -Be $false
            }

            It 'Returns true if the regex matches' {
                Test-FeatureFlag "well-tested" "Storage/master" $config | Should -Be $true
            }
        }

        Context 'Chained whitelist configuration' {
            $serializedConfig = @"
            {
                "stages": {
                    "test-repo-and-branch": [
                        {"whitelist": [
                            "storage1/.*",
                            "storage2/dev-branch"
                        ]}
                    ]
                },
                "features": {
                    "experimental-feature": {
                        "stages": ["test-repo-and-branch"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig $serializedConfig
            $config = ConvertFrom-Json $serializedConfig

            It 'Returns true if the regex matches' {
                Test-FeatureFlag "experimental-feature" "storage1/master" $config | Should -Be $true
                Test-FeatureFlag "experimental-feature" "storage1/dev" $config | Should -Be $true
                Test-FeatureFlag "experimental-feature" "storage2/dev-branch" $config | Should -Be $true
            }
            It 'Returns false if the regex does not match' {
                Test-FeatureFlag "experimental-feature" "storage2/master" $config | Should -Be $false
            }
        }
    }

    Context 'Blacklist condition' {
        Context 'Reject-all configuration' {
            $serializedConfig = @"
            {
                "stages": {
                    "none": [
                        {"blacklist": [".*"]}
                    ]
                },
                "features": {
                    "disabled": {
                        "stages": ["none"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig $serializedConfig
            $config = ConvertFrom-Json $serializedConfig

            It 'Rejects everything' {
                Test-FeatureFlag "disabled" "Storage/master" $config | Should -Be $false
                Test-FeatureFlag "disabled" "foo" $config | Should -Be $false
                Test-FeatureFlag "disabled" "bar" $config | Should -Be $false
            }
        }

        Context 'Reject single-value configuration' {
            $serializedConfig = @"
            {
                "stages": {
                    "all-except-important": [
                        {"blacklist": ["^important$"]}
                    ]
                },
                "features": {
                    "some-feature":
                    {
                        "stages": ["all-except-important"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig $serializedConfig
            $config = ConvertFrom-Json $serializedConfig

            # Given that the regex is ^important$, only the exact string "important" will match the blacklist.
            It 'Allows the flag if the predicate does not match exactly' {
                Test-FeatureFlag "some-feature" "Storage/master" $config | Should -Be $true
                Test-FeatureFlag "some-feature" "foo" $config | Should -Be $true
                Test-FeatureFlag "some-feature" "bar" $config | Should -Be $true
                Test-FeatureFlag "some-feature" "Storage/important" $config | Should -Be $true
            }

            It 'Rejects the flag only if the predicate matches exactly the regex' {
                Test-FeatureFlag "some-feature" "important" $config | Should -Be $false
            }
        }

        Context 'Reject multiple-value configuration' {
            $serializedConfig = @"
            {
                "stages": {
                    "all-except-important": [
                        {"blacklist": ["storage-important/master", "storage-important2/master"]}
                    ]
                },
                "features": {
                    "some-feature": {
                        "stages": ["all-except-important"]
                    }
                }
            }
"@
            Confirm-FeatureFlagConfig $serializedConfig
            $config = ConvertFrom-Json $serializedConfig

            It 'Allows predicates not matching the blacklist' {
                Test-FeatureFlag "some-feature" "storage1/master" $config | Should -Be $true
                Test-FeatureFlag "some-feature" "storage2/master" $config | Should -Be $true
                Test-FeatureFlag "some-feature" "storage-important/dev" $config | Should -Be $true
            }

            It 'Rejects important / important2 master branches' {
                Test-FeatureFlag "some-feature" "storage-important/master" $config | Should -Be $false
                Test-FeatureFlag "some-feature" "storage-important2/master" $config | Should -Be $false
            }
        }
    }

    Context 'Mixed whitelist/blacklist configuration' {
        $serializedConfig = @"
        {
            "stages": {
                "all-storage-important": [
                    {"whitelist": ["storage.*"]},
                    {"blacklist": ["storage-important/master", "storage-important2/master"]}
                ]
            },
            "features": {
                "some-feature": {
                    "stages": ["all-storage-important"]
                }
            }
        }
"@
        Confirm-FeatureFlagConfig $serializedConfig
        $config = ConvertFrom-Json $serializedConfig

        It 'Rejects storage important / important2 master branches' {
            Test-FeatureFlag "some-feature" "storage-important/master" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "storage-important2/master" $config | Should -Be $false
        }

        It 'Rejects non-storage predicates' {
            Test-FeatureFlag "some-feature" "compute/master" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "something-else/master" $config | Should -Be $false
        }

        It 'Allows other storage predicates' {
            Test-FeatureFlag "some-feature" "storage-important/dev" $config | Should -Be $true
            Test-FeatureFlag "some-feature" "storage-somethingelse/dev" $config | Should -Be $true
            Test-FeatureFlag "some-feature" "storage-dev/master" $config | Should -Be $true
        }
    }

    Context 'Probability condition' {
        $serializedConfig = @"
        {
            "stages": {
                "all": [
                    {"probability": 1}
                ],
                "none": [
                    {"probability": 0}
                ],
                "10percent": [
                    {"probability": 0.1}
                ]
            },
            "features": {
                "well-tested": {
                    "stages": ["all"]
                },
                "not-launched": {
                    "stages": ["none"]
                },
                "10pc-feature": {
                    "stages": ["10percent"]
                }
            }
        }
"@
        Confirm-FeatureFlagConfig $serializedConfig
        $config = ConvertFrom-Json $serializedConfig

        It 'Always allows with probability 1' {
            Test-FeatureFlag "well-tested" "storage-important/master" $config | Should -Be $true
            Test-FeatureFlag "well-tested" "foo" $config | Should -Be $true
            Test-FeatureFlag "well-tested" "bar" $config | Should -Be $true
        }

        It 'Always rejects with probability 0' {
            Test-FeatureFlag "not-launched" "storage-important/master" $config | Should -Be $false
            Test-FeatureFlag "not-launched" "foo" $config | Should -Be $false
            Test-FeatureFlag "not-launched" "bar" $config | Should -Be $false
        }

        # It's not best practice to test external behavior based on implementation, but this is probably
        # the best way to test the probability condition without extracting away its inner logic and mocking
        # it.
        It 'Allows features if the random value is below the probability threshold' {
            # The probability condition generates a random number, computes mod 100 and then scales back the
            # results between 0 and 1 to compare it with the given probability, returning true if the generated
            # number is less than the probability.

            # If Get-Random returns 1, the probability will be 0.01, less than the given 0.1 percent, therefore
            # enabling the feature.
            Mock Get-Random -ModuleName FeatureFlags {return 1} 
            Test-FeatureFlag "10pc-feature" "storage-important/master" $config | Should -Be $true
            Test-FeatureFlag "10pc-feature" "storage/master" $config | Should -Be $true
            Test-FeatureFlag "10pc-feature" "storage/dev" $config | Should -Be $true
            Test-FeatureFlag "10pc-feature" "storage-important/dev" $config | Should -Be $true
        }

        It 'Rejects features if the random value is above the probability threshold' {
            # If Get-Random returns 99, the probability will be 0.99, greater than the given 0.1 percent,
            # therefore not enabling the feature.
            Mock Get-Random -ModuleName FeatureFlags  {return 99} 
            Test-FeatureFlag "10pc-feature" "storage-important/master" $config | Should -Be $false
            Test-FeatureFlag "10pc-feature" "storage-important/master" $config | Should -Be $false
            Test-FeatureFlag "10pc-feature" "storage-important/master" $config | Should -Be $false
        }
    }

    Context 'Complex whitelist + blacklist + probability configuration' {
        $serializedConfig = @"
        {
            "stages": {
                "all-storage-important-50pc": [
                    {"whitelist": ["storage.*"]},
                    {"blacklist": ["storage-important/master", "storage-important2/master"]},
                    {"probability": 0.5}
                ]
            },
            "features": {
                "some-feature": {
                    "stages": ["all-storage-important-50pc"]
                }
            }
        }
"@

        Confirm-FeatureFlagConfig $serializedConfig
        $config = ConvertFrom-Json $serializedConfig

        It 'Rejects storage important / important2 master branches' {
            Test-FeatureFlag "some-feature" "storage-important/master" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "storage-important2/master" $config | Should -Be $false
        }

        It 'Rejects non-storage predicates' {
            Test-FeatureFlag "some-feature" "compute/master" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "something-else/master" $config | Should -Be $false
        }

        It 'Rejects storage predicates for high values of Get-Random' {
            Mock Get-Random -ModuleName FeatureFlags {return 90} 
            Test-FeatureFlag "some-feature" "storage-important/dev" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "storage-somethingelse/dev" $config | Should -Be $false
            Test-FeatureFlag "some-feature" "storage-dev/master" $config | Should -Be $false
        }

        It 'Accepts storage predicates for low values of Get-Random' {
            Mock Get-Random -ModuleName FeatureFlags {return 20} 
            Test-FeatureFlag "some-feature" "storage-important/dev" $config | Should -Be $true
            Test-FeatureFlag "some-feature" "storage-somethingelse/dev" $config | Should -Be $true
            Test-FeatureFlag "some-feature" "storage-dev/master" $config | Should -Be $true
        }
    }
}

Describe 'Get-EvaluatedFeatureFlags' -Tag Features {
    Context 'Verify evaluation of all feature flags' {
        $serializedConfig = Get-Content -Raw "$PSScriptRoot\multiple-stages-features.json"
        Confirm-FeatureFlagConfig $serializedConfig
        $config = ConvertFrom-Json $serializedConfig;
        Mock New-Item -ModuleName FeatureFlags {}

        It 'Returns expected feature flags' {
            $expected = @{ "filetracker"=$true; "newestfeature"=$true; "testfeature"=$false }
            $actual = Get-EvaluatedFeatureFlags -predicate "production/some-repo" -config $config

            Test-Hashtables $expected $actual
        }
    }
}

Describe 'Out-EvaluatedFeaturesFiles' -Tag Features {
    Context 'Verify output file content' {
        $global:featuresJsonContent = New-Object 'System.Collections.ArrayList()'
        $global:featuresIniContent = New-Object 'System.Collections.ArrayList()'
        $global:featuresEnvConfigContent = New-Object 'System.Collections.ArrayList()'

        $serializedConfig = Get-Content -Raw "$PSScriptRoot\multiple-stages-features.json"
        Confirm-FeatureFlagConfig $serializedConfig
        $config = ConvertFrom-Json $serializedConfig

        Mock -ModuleName FeatureFlags New-Item {}
        Mock -ModuleName $ModuleName Test-Path { Write-Output $true }
        Mock -ModuleName $ModuleName Remove-Item {}
        Mock -ModuleName $ModuleName Out-File { ${global:featuresJsonContent}.Add($InputObject) } -ParameterFilter { $FilePath.EndsWith("features.json") }
        Mock -ModuleName $ModuleName Add-Content { ${global:featuresIniContent}.Add($Value) } -ParameterFilter  { $Path.EndsWith("features.ini") }
        Mock -ModuleName $ModuleName Add-Content { ${global:featuresEnvConfigContent}.Add($Value) } -ParameterFilter { $Path.EndsWith("features.env.config") }

        It 'Honors blacklist' {
            $features = Get-EvaluatedFeatureFlags -predicate "important" -config $config
            $expectedFeaturesIniContent = @("filetracker`tfalse", "newestfeature`tfalse", "testfeature`tfalse")
            $expectedFeaturesEnvConfigContent = @()

            Out-EvaluatedFeaturesFiles -Config $config -EvaluatedFeatures $features -OutputFolder 'outputfolder.mock'

            # Validate JSON
            $global:featuresJsonContent | Should -Not -Be $null
            $global:featuresJsonContent.Count | Should -Be 1
            $jsonContent = ConvertFrom-Json -InputObject $global:featuresJsonContent[0]
            $jsonContent.filetracker | Should -Be $false
            $jsonContent.newestfeature | Should -Be $false
            $jsonContent.testfeature | Should -Be $false

            # Validate INI
            Test-StringArrays ($expectedFeaturesIniContent | Sort-Object) ($global:featuresIniContent | Sort-Object)

            # Validate Env
            $global:featuresEnvConfigContent.Count | Should -Be 0
            $global:featuresEnvConfigContent | Should -Be $expectedFeaturesEnvConfigContent
        }
    }
}

Remove-Module $ModuleName
Remove-Module test-functions