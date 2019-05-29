# Copyright (c) Microsoft Corporation. All rights reserved.

Function Test-StringArrays
{
    <#
    .SYNOPSIS
    Uses Pester assertions to test two string arrays for equality.

    .NOTES
    Pester does not have array assertions =(
    #>
    Param
    (
        [Parameter(Position=0)]
        [AllowNull()]
        [string[]] $Expected,

        [Parameter(Position=1)]
        [AllowNull()]
        [string[]] $Actual
    )

    if ($null -eq $Actual)
    {
        $Expected | Should Be $null
        return
    }

    # Actual is not null
    if ($null -eq $Expected)
    {
        throw "Expected string[] is null and Actual is not null"
    }

    if ($Actual.Count -ne $Expected.Count)
    {
        Write-Host "  Actual: $Actual" -ForegroundColor Red
        Write-Host "Expected: $Expected" -ForegroundColor Red
    }

    $Actual.Count | Should Be $Expected.Count

    for ($i = 0; $i -lt $Actual.Count; $i++)
    {
        $Actual[$i] | Should Be $Expected[$i]
    }
}

Function Test-ObjectArrays
{
    <#
    .SYNOPSIS
    Uses Pester assertions to test two string arrays for equality.

    .NOTES
    Pester does not have array assertions =(
    #>
    Param
    (
        [Parameter(Position=0)]
        [AllowNull()]
        [Array] $Expected,

        [Parameter(Position=1)]
        [AllowNull()]
        [Array] $Actual
    )

    if ($Actual -eq $null)
    {
        $Expected | Should Be $null
        return
    }

    # Actual is not null
    if ($Expected -eq $null)
    {
        throw "Expected Array is null and Actual is not null"
    }

    if ($Actual.Count -ne $Expected.Count)
    {
        Write-Host "  Actual: $Actual" -ForegroundColor Red
        Write-Host "Expected: $Expected" -ForegroundColor Red
    }

    $Actual.Count | Should Be $Expected.Count

    for ($i = 0; $i -lt $Actual.Count; $i++)
    {
        Test-Hashtables $Expected[$i] $Actual[$i]
    }
}

Function Test-Hashtables
{
    <#
    .SYNOPSIS
    Uses Pester assertions to test two hashtables for equality.

    .NOTES
    Pester does not have hashtable assertions =(
    #>
    Param
    (
        [Parameter(Position=0)]
        [AllowNull()]
        [Hashtable] $Expected,

        [Parameter(Position=1)]
        [AllowNull()]
        [Hashtable] $Actual
    )

    if ($Expected -eq $null)
    {
        $Actual | Should Be $null
        return
    }

    if ($Actual -eq $null)
    {
        $Expected | Should Be $null
        return
    }

    if ($Actual.Count -eq 0 -and $Expected.Count -eq 0)
    {
        # Redundant, but tells Pester we tested something
        # If the counts don't match, continue with the comparison so we contain
        # find out what's missing in the test error log
        $Actual.Count | Should Be $Expected.Count
        return
    }

    foreach ($actualProperty in $Actual.GetEnumerator())
    {
        if ($Expected.Contains($actualProperty.Name))
        {
            $expectedValue = $Expected[$actualProperty.Name]

            if ($null -eq $actualProperty.Value)
            {
                $actualProperty.Value | Should Be $expectedValue
            }
            else
            {
                $actualProperty.Value.GetType() | Should Be $expectedValue.GetType()

                if ($expectedValue.GetType().FullName -eq 'System.Collections.Hashtable')
                {
                    Test-Hashtables -Actual $actualProperty.Value -Expected $expectedValue
                }
                elseif ($actualProperty.Value.GetType() -imatch ".*Array$|.*\[\]$")
                {
                    if ($actualProperty.Value[0].GetType().FullName -ieq 'System.String')
                    {
                        Test-StringArrays $expectedProperty.Value $actualValue
                    }
                    elseif ($actualProperty.Value[0].GetType().FullName -ieq 'System.Collections.Hashtable')
                    {
                        Test-ObjectArrays -Actual $actualValue -Expected $expectedProperty.Value
                    }
                    else
                    {
                        # Just assert their lengths for now
                        $actualProperty.Value.Count | Should Be $expectedValue.Count    
                    }
                }
                else
                {
                    $actualProperty.Value | Should Be $expectedValue
                }   
            }
        }
        else
        {
            throw "Expected did not contain an actual value:`nKey = $($actualProperty.Name)`nValue = $($actualProperty.Value)"    
        }
    }

    foreach ($expectedProperty in $Expected.GetEnumerator())
    {
        if ($Actual.Contains($expectedProperty.Name))
        {
            $actualValue = $Actual[$expectedProperty.Name]

            if ($null -eq $expectedProperty.Value)
            {
                $actualValue | Should Be $expectedProperty.Value
            }
            else
            {
                $actualValue.GetType() | Should Be $expectedProperty.Value.GetType()

                if ($expectedProperty.Value.GetType().FullName -eq 'System.Collections.Hashtable')
                {
                    Test-Hashtables -Actual $actualValue -Expected $expectedProperty.Value
                }
                elseif ($expectedProperty.Value.GetType() -imatch ".*Array$|.*\[\]$")
                {
                    if ($expectedProperty.Value[0].GetType().FullName -imatch 'System.String')
                    {
                        Test-StringArrays $expectedProperty.Value $actualValue
                    }
                    elseif ($expectedProperty.Value[0].GetType().FullName -imatch 'System.Collections.Hashtable')
                    {
                        Test-ObjectArrays -Actual $actualValue -Expected $expectedProperty.Value
                    }
                    else
                    {
                        # Just assert their lengths for now
                        $actualValue.Count | Should Be $expectedProperty.Value.Count    
                    }
                }
                else
                {
                    $actualValue | Should Be $expectedProperty.Value
                }
            }
        }
        else
        {
            throw "Actual did not contain an expected value:`nKey = $($expectedProperty.Name)`nValue = $($expectedProperty.Value)"    
        }
    }
}

Export-ModuleMember `
    -Function @(
        'Test-StringArrays',
        'Test-Hashtables'
    )