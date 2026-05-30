BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Connect-SsisCatalog' {
    It 'Returns an IntegrationServices object unchanged when one is passed in' {
        InModuleScope $script:moduleName {
            $fake = [PSCustomObject]@{ Marker = 'reuse' }
            $fake.PSObject.TypeNames.Insert(0, 'Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices')

            $result = Connect-SsisCatalog -SqlInstance $fake

            $result.Marker | Should -Be 'reuse'
        }
    }

    It 'Exposes -SqlInstance and -SqlCredential parameters' {
        InModuleScope $script:moduleName {
            (Get-Command -Name Connect-SsisCatalog).Parameters.Keys | Should -Contain 'SqlInstance'
            (Get-Command -Name Connect-SsisCatalog).Parameters.Keys | Should -Contain 'SqlCredential'
        }
    }
}
