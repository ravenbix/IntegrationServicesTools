BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisCatalogObject' {
    It 'Assigns every supplied property, calls Alter and returns the catalog' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with settable properties and an Alter() ScriptMethod is a faithful
            # stand-in for the MOM Catalog: the wrapper only assigns properties and calls Alter().
            $catalog = [PSCustomObject]@{
                MaxProjectVersions        = 0
                OperationLogRetentionTime = 0
                AlterCalled               = $false
            }
            $catalog | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            $result = Set-SsisCatalogObject -Catalog $catalog -Property @{ MaxProjectVersions = 5; OperationLogRetentionTime = 365 }

            $result.MaxProjectVersions | Should -Be 5
            $result.OperationLogRetentionTime | Should -Be 365
            $result.AlterCalled | Should -BeTrue
        }
    }

    It 'Only changes the properties present in the hashtable' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{
                MaxProjectVersions        = 10
                OperationLogRetentionTime = 99
            }
            $catalog | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { }

            $null = Set-SsisCatalogObject -Catalog $catalog -Property @{ MaxProjectVersions = 5 }

            $catalog.MaxProjectVersions | Should -Be 5
            $catalog.OperationLogRetentionTime | Should -Be 99
        }
    }
}
