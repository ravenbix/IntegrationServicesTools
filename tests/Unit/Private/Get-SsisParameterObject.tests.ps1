BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisParameterObject' {
    It 'Returns the named parameter when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Parameters collection: it supports both
            # .Contains(name) and the [name] indexer.
            $parameter = [PSCustomObject]@{ Name = 'TargetPort' }
            $container = [PSCustomObject]@{ Parameters = @{ 'TargetPort' = $parameter } }

            $result = Get-SsisParameterObject -Container $container -Name 'TargetPort'

            $result.Name | Should -Be 'TargetPort'
        }
    }

    It 'Returns $null when the named parameter does not exist' {
        InModuleScope $script:moduleName {
            $container = [PSCustomObject]@{ Parameters = @{} }

            $result = Get-SsisParameterObject -Container $container -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Parameters collection when no name is given' {
        InModuleScope $script:moduleName {
            $container = [PSCustomObject]@{
                Parameters = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisParameterObject -Container $container

            $result.Count | Should -Be 2
        }
    }
}
