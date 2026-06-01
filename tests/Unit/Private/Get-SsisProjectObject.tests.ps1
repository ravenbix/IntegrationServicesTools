BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisProjectObject' {
    It 'Returns the named project when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Projects collection: it
            # supports both .Contains(name) and the [name] indexer.
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $folder = [PSCustomObject]@{ Projects = @{ 'Sales' = $project } }

            $result = Get-SsisProjectObject -Folder $folder -Name 'Sales'

            $result.Name | Should -Be 'Sales'
        }
    }

    It 'Returns $null when the named project does not exist' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{ Projects = @{} }

            $result = Get-SsisProjectObject -Folder $folder -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Projects collection when no name is given' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{
                Projects = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisProjectObject -Folder $folder

            $result.Count | Should -Be 2
        }
    }
}
