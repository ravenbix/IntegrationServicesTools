BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionObject' {
    It 'Returns the whole Executions collection when no id is given' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Executions = @('exec1', 'exec2') }
            $result = Get-SsisExecutionObject -Catalog $catalog
            $result | Should -Be @('exec1', 'exec2')
        }
    }

    It 'Indexes the collection by id when -ExecutionId is given' {
        InModuleScope $script:moduleName {
            # A hashtable exposes the same [] indexer semantics as the real MOM collection.
            $executions = @{ [long]42 = 'exec-42' }
            $catalog = [PSCustomObject]@{ Executions = $executions }

            $result = Get-SsisExecutionObject -Catalog $catalog -ExecutionId 42
            $result | Should -Be 'exec-42'
        }
    }
}
