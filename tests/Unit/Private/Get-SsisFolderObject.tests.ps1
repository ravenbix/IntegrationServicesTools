BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisFolderObject' {
    It 'Returns the named folder when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Folders collection: it
            # supports both .Contains(name) and the [name] indexer.
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $catalog = [PSCustomObject]@{ Folders = @{ 'Finance' = $folder } }

            $result = Get-SsisFolderObject -Catalog $catalog -Name 'Finance'

            $result.Name | Should -Be 'Finance'
        }
    }

    It 'Returns $null when the named folder does not exist' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Folders = @{} }

            $result = Get-SsisFolderObject -Catalog $catalog -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Folders collection when no name is given' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{
                Folders = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisFolderObject -Catalog $catalog

            $result.Count | Should -Be 2
        }
    }
}
