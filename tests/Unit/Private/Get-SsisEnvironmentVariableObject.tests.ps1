BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentVariableObject' {
    It 'Returns the named variable when it exists' {
        InModuleScope $script:moduleName {
            $variable = [PSCustomObject]@{ Name = 'ConnString' }
            $environment = [PSCustomObject]@{ Variables = @{ 'ConnString' = $variable } }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'ConnString'

            $result.Name | Should -Be 'ConnString'
        }
    }

    It 'Returns $null when the named variable does not exist' {
        InModuleScope $script:moduleName {
            $environment = [PSCustomObject]@{ Variables = @{} }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Variables collection when no name is given' {
        InModuleScope $script:moduleName {
            $environment = [PSCustomObject]@{
                Variables = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment

            $result.Count | Should -Be 2
        }
    }
}
