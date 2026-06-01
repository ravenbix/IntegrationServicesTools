BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisParameterObject' {
    It 'Sets a literal value on the parameter and alters the project' {
        InModuleScope $script:moduleName {
            $parameter = [PSCustomObject]@{ SetType = $null; SetValue = $null }
            $parameter | Add-Member -MemberType 'ScriptMethod' -Name 'Set' -Value {
                param ($valueType, $value)
                $this.SetType = $valueType
                $this.SetValue = $value
            }

            $project = [PSCustomObject]@{ AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisParameterObject -Parameter $parameter -ValueType 'Literal' -Value 1450 -Project $project

            $parameter.SetValue | Should -Be 1450
            $parameter.SetType.ToString() | Should -Be 'Literal'
            $project.AlterCalled | Should -BeTrue
        }
    }

    It 'Sets a referenced value on the parameter' {
        InModuleScope $script:moduleName {
            $parameter = [PSCustomObject]@{ SetType = $null; SetValue = $null }
            $parameter | Add-Member -MemberType 'ScriptMethod' -Name 'Set' -Value {
                param ($valueType, $value)
                $this.SetType = $valueType
                $this.SetValue = $value
            }

            $project = [PSCustomObject]@{ AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisParameterObject -Parameter $parameter -ValueType 'Referenced' -Value 'Port' -Project $project

            $parameter.SetValue | Should -Be 'Port'
            $parameter.SetType.ToString() | Should -Be 'Referenced'
        }
    }
}
