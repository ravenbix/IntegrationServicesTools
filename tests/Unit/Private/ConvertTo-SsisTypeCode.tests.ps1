BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-SsisTypeCode' {
    Context 'Inference from the value .NET type' {
        It 'Maps <Label> to <Expected>' -ForEach @(
            @{ Label = 'Int32';    Value = [int]42;            Expected = 'Int32' }
            @{ Label = 'Int64';    Value = [long]42;           Expected = 'Int64' }
            @{ Label = 'String';   Value = 'hello';            Expected = 'String' }
            @{ Label = 'Boolean';  Value = $true;              Expected = 'Boolean' }
            @{ Label = 'Decimal';  Value = [decimal]1.5;       Expected = 'Decimal' }
            @{ Label = 'Double';   Value = [double]1.5;        Expected = 'Double' }
            @{ Label = 'DateTime'; Value = [datetime]'2026-01-01'; Expected = 'DateTime' }
        ) {
            InModuleScope $script:moduleName -Parameters $PSItem {
                param ($Value, $Expected)
                (ConvertTo-SsisTypeCode -Value $Value).ToString() | Should -Be $Expected
            }
        }

        It 'Defaults a null value to String' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value $null).ToString() | Should -Be 'String'
            }
        }
    }

    Context 'Explicit -DataType override' {
        It 'Returns the named type code regardless of the value type' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value 'hello' -DataType 'Int32').ToString() | Should -Be 'Int32'
            }
        }

        It 'Is case-insensitive' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value 1 -DataType 'int64').ToString() | Should -Be 'Int64'
            }
        }

        It 'Throws on an unsupported data type name' {
            InModuleScope $script:moduleName {
                { ConvertTo-SsisTypeCode -Value 1 -DataType 'Guid' } | Should -Throw -ExpectedMessage '*Guid*'
            }
        }
    }
}
