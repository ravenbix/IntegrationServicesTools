BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisOperationObject' {
    It 'Returns the whole Operations collection when no id is given' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Operations = @('op1', 'op2') }

            $result = Get-SsisOperationObject -Catalog $catalog
            $result | Should -HaveCount 2
            $result[0] | Should -Be 'op1'
            $result[1] | Should -Be 'op2'
        }
    }

    It 'Indexes the collection by id when -OperationId is given' {
        InModuleScope $script:moduleName {
            # A hashtable exposes the same [] indexer semantics as the real MOM collection.
            $operations = @{ [long]7 = 'op-7' }
            $catalog = [PSCustomObject]@{ Operations = $operations }

            $result = Get-SsisOperationObject -Catalog $catalog -OperationId 7
            $result | Should -Be 'op-7'
        }
    }
}
