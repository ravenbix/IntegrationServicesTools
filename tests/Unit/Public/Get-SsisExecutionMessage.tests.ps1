BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionMessage' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        $script:messages = @(
            [PSCustomObject]@{ Id = 1; Message = 'Start'; MessageType = 70 }
            [PSCustomObject]@{ Id = 2; Message = 'Boom'; MessageType = 120 }
        )
    }

    It 'Returns messages for an execution by id, decorated as Ssis.ExecutionMessage' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42 }
        } -ParameterFilter { $ExecutionId -eq 42 }
        Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 42
        ($result | Measure-Object).Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'Ssis.ExecutionMessage'
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 1 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Warns and returns nothing when the execution is not found' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 999 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Reads messages off a piped Ssis.Execution without reconnecting' {
            Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

            $execution = [PSCustomObject]@{ Id = 5 }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $result = $execution | Get-SsisExecutionMessage
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 2
        }
    }
}
