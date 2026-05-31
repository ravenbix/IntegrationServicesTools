BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisCatalogObject' {
    It 'Returns the SSISDB catalog when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Catalogs collection: it
            # supports both .Contains(name) and the [name] indexer.
            $catalog = [PSCustomObject]@{ Name = 'SSISDB' }
            $integrationServices = [PSCustomObject]@{ Catalogs = @{ 'SSISDB' = $catalog } }

            $result = Get-SsisCatalogObject -IntegrationServices $integrationServices

            $result.Name | Should -Be 'SSISDB'
        }
    }

    It 'Returns $null when the catalog does not exist' {
        InModuleScope $script:moduleName {
            $integrationServices = [PSCustomObject]@{ Catalogs = @{} }

            $result = Get-SsisCatalogObject -IntegrationServices $integrationServices

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Looks up a custom catalog name when -Name is supplied' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Name = 'Custom' }
            $integrationServices = [PSCustomObject]@{ Catalogs = @{ 'Custom' = $catalog } }

            $result = Get-SsisCatalogObject -IntegrationServices $integrationServices -Name 'Custom'

            $result.Name | Should -Be 'Custom'
        }
    }
}
