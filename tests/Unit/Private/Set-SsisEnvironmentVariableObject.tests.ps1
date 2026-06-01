BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisEnvironmentVariableObject' {
    It 'Adds a new variable and alters the environment when the variable does not exist' {
        InModuleScope $script:moduleName {
            # Variables stand-in for the create branch: .Contains returns false; .Add captures its args.
            # No indexer is needed because the create branch never indexes.
            $variables = [PSCustomObject]@{ Added = $null }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Contains' -Value { param ($n) $false }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($name, $type, $value, $sensitive, $description)
                $this.Added = [PSCustomObject]@{ Name = $name; Type = $type; Value = $value; Sensitive = $sensitive; Description = $description }
            }

            $environment = [PSCustomObject]@{ Variables = $variables; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $false -Description 'db port'

            $environment.Variables.Added.Name | Should -Be 'Port'
            $environment.Variables.Added.Value | Should -Be 1433
            $environment.Variables.Added.Type | Should -Be ([System.TypeCode]::Int32)
            $environment.Variables.Added.Sensitive | Should -BeFalse
            $environment.AlterCalled | Should -BeTrue
        }
    }

    It 'Updates the existing variable value and alters the environment when the variable exists' {
        InModuleScope $script:moduleName {
            # Update branch: a hashtable supports .Contains(name) (IDictionary.Contains) and the [name]
            # indexer, returning the live variable object the wrapper mutates.
            $existing = [PSCustomObject]@{ Name = 'Port'; Value = 1; Sensitive = $false; Description = 'old' }
            $environment = [PSCustomObject]@{ Variables = @{ 'Port' = $existing }; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $true -Description 'db port'

            $existing.Value | Should -Be 1433
            $existing.Sensitive | Should -BeTrue
            $existing.Description | Should -Be 'db port'
            $environment.AlterCalled | Should -BeTrue
        }
    }
}
