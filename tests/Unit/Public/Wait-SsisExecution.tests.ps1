BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Wait-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Start-Sleep -ModuleName $script:moduleName -MockWith { }
    }

    It 'Polls until a terminal status, then returns the completed execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        $script:statuses = @('Running', 'Running', 'Success')
        $script:callIndex = 0
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            $status = $script:statuses[$script:callIndex]
            $script:callIndex++
            [PSCustomObject]@{ Id = 7; Status = $status }
        }

        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 1
        $result.Status | Should -Be 'Success'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        Should -Invoke -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -Times 3 -Scope It
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Times 2 -Scope It
    }

    It 'On timeout, writes a non-terminating error and returns the still-running execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }

        $errors = @()
        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 5 -Timeout 10 -ErrorVariable errors -ErrorAction SilentlyContinue
        $result.Status | Should -Be 'Running'
        $errors.Count | Should -BeGreaterThan 0
    }

    It 'Honours -ErrorAction Stop on timeout' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }

        { Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 5 -Timeout 5 -ErrorAction Stop } |
            Should -Throw
    }

    It 'Rejects a PollInterval below 1' {
        { Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 0 } |
            Should -Throw
    }

    It 'Sleeps for the custom -PollInterval between refreshes' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        $script:statuses = @('Running', 'Success')
        $script:callIndex = 0
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            $status = $script:statuses[$script:callIndex]
            $script:callIndex++
            [PSCustomObject]@{ Id = 7; Status = $status }
        }

        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 15
        $result.Status | Should -Be 'Success'
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Seconds -eq 15 }
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Success' }
        }
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Wait-SsisExecution -SqlInstance 'TestInstance' -SqlCredential $credential -ExecutionId 7

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }

        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Warns and returns nothing when the execution is not found' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null }

        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 999 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Waits on a piped execution without reconnecting' {
            Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
                [PSCustomObject]@{ Id = 7; Status = 'Success' }
            }

            $execution = [PSCustomObject]@{ Id = 7; Status = 'Running' }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $result = $execution | Wait-SsisExecution -PollInterval 1
            $result.Status | Should -Be 'Success'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Times out on a piped execution when -Timeout elapses' {
            Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
                [PSCustomObject]@{ Id = 7; Status = 'Running' }
            }

            $execution = [PSCustomObject]@{ Id = 7; Status = 'Running' }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $errors = @()
            $result = $execution | Wait-SsisExecution -PollInterval 5 -Timeout 5 -ErrorVariable errors -ErrorAction SilentlyContinue
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            $result.Status | Should -Be 'Running'
            $errors.Count | Should -BeGreaterThan 0
        }
    }
}
