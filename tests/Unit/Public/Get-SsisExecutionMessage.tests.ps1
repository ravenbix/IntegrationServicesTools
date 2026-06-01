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

    It 'Passes -SqlCredential through to Connect-SsisCatalog with -ExecutionId' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42 }
        }
        Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -SqlCredential $credential -ExecutionId 42

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Lets callers narrow the returned log by MessageType with Where-Object' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42 }
        }
        Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 42 |
            Where-Object -FilterScript { $_.MessageType -eq 120 }

        ($result | Measure-Object).Count | Should -Be 1
        $result.MessageType | Should -Be 120
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
