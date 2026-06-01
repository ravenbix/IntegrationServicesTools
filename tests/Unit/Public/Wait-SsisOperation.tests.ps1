BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Wait-SsisOperation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Start-Sleep -ModuleName $script:moduleName -MockWith { }
    }

    It 'Polls until a terminal status, then returns the completed operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        $script:statuses = @('Running', 'Running', 'Success')
        $script:callIndex = 0
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            $status = $script:statuses[$script:callIndex]
            $script:callIndex++
            [PSCustomObject]@{ Id = 9; Status = $status }
        }

        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 1
        $result.Status | Should -Be 'Success'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        Should -Invoke -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -Times 3 -Scope It
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Times 2 -Scope It
    }

    It 'On timeout, writes a non-terminating error and returns the still-running operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }

        $errors = @()
        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 5 -Timeout 10 -ErrorVariable errors -ErrorAction SilentlyContinue
        $result.Status | Should -Be 'Running'
        $errors.Count | Should -BeGreaterThan 0
    }

    It 'Honours -ErrorAction Stop on timeout' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }

        { Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 5 -Timeout 5 -ErrorAction Stop } |
            Should -Throw
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Success' }
        }

        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Wait-SsisOperation -SqlInstance 'TestInstance' -SqlCredential $credential -OperationId 9 -PollInterval 1

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Returns immediately without sleeping when already terminal, even with a -Timeout set' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Success' }
        }

        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 1 -Timeout 30
        $result.Status | Should -Be 'Success'
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and returns nothing when the operation is absent' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 404 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Rejects a PollInterval below 1' {
        { Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 0 } |
            Should -Throw
    }

    Context 'ByObject' {
        It 'Waits on a piped operation without reconnecting' {
            Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
                [PSCustomObject]@{ Id = 9; Status = 'Success' }
            }

            $operation = [PSCustomObject]@{ Id = 9; Status = 'Running' }
            $operation.PSObject.TypeNames.Insert(0, 'Ssis.Operation')

            $result = $operation | Wait-SsisOperation -PollInterval 1
            $result.Status | Should -Be 'Success'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }
}
