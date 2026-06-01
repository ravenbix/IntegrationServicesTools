BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentObject' {
    It 'Returns the named environment when it exists' {
        InModuleScope $script:moduleName {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $folder = [PSCustomObject]@{ Environments = @{ 'Prod' = $environment } }

            $result = Get-SsisEnvironmentObject -Folder $folder -Name 'Prod'

            $result.Name | Should -Be 'Prod'
        }
    }

    It 'Returns $null when the named environment does not exist' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{ Environments = @{} }

            $result = Get-SsisEnvironmentObject -Folder $folder -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Environments collection when no name is given' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{
                Environments = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisEnvironmentObject -Folder $folder

            $result.Count | Should -Be 2
        }
    }
}
