BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Stop-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Canceled' }
        }
    }

    It 'Stops the execution and emits nothing by default' {
        $result = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -Confirm:$false
        $result | Should -BeNullOrEmpty
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Returns the refreshed execution with -PassThru' {
        $result = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PassThru -Confirm:$false
        $result.Status | Should -Be 'Canceled'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
    }

    It 'Supports -WhatIf and does not stop' {
        $null = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -WhatIf
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not stop when the execution does not exist' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null }
        $errors = @()
        $null = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 999 -Confirm:$false -ErrorVariable errors -ErrorAction SilentlyContinue
        $errors.Count | Should -BeGreaterThan 0
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Stops a piped execution without reconnecting' {
            $execution = [PSCustomObject]@{ Id = 7; Status = 'Running' }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $null = $execution | Stop-SsisExecution -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
        }
    }
}
