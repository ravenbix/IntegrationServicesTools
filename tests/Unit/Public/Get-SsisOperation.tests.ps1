BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisOperation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        # Three operations spanning two types and two statuses.
        $script:allOps = @(
            [PSCustomObject]@{ Id = 1; OperationType = 300; Status = 'Success' }
            [PSCustomObject]@{ Id = 2; OperationType = 300; Status = 'Failed' }
            [PSCustomObject]@{ Id = 3; OperationType = 101; Status = 'Success' }
        )
    }

    It 'Returns a single operation by id, decorated as Ssis.Operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; OperationType = 300; Status = 'Success' }
        } -ParameterFilter { $OperationId -eq 9 }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -OperationId 9
        $result.Id | Should -Be 9
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
    }

    It 'Filters by -Status' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -Status 'Success'
        ($result | Measure-Object).Count | Should -Be 2
        $result.Status | Should -Not -Contain 'Failed'
    }

    It 'Caps to the most recent N with -Top, highest Id first' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -Top 2
        ($result | Measure-Object).Count | Should -Be 2
        $result[0].Id | Should -Be 3
        $result[1].Id | Should -Be 2
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisOperation -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Lists operations of a piped Ssis.Catalog without reconnecting' {
            Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

            $catalog = [PSCustomObject]@{ Name = 'SSISDB' }
            $catalog.PSObject.TypeNames.Insert(0, 'Ssis.Catalog')

            $result = $catalog | Get-SsisOperation
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 3
        }
    }
}
