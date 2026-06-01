BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Name = 'Sales' }
        }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' })
        }
        Mock -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -MockWith { [long] 55 }
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 55; Status = 'Running' }
        } -ParameterFilter { $ExecutionId -eq 55 }
        Mock -CommandName Wait-SsisExecution -ModuleName $script:moduleName -MockWith {
            $obj = [PSCustomObject]@{ Id = 55; Status = 'Success' }
            $obj.PSObject.TypeNames.Insert(0, 'Ssis.Execution')
            $obj
        }
    }

    It 'Starts the package and returns the new Ssis.Execution' {
        $result = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false
        $result.Id | Should -Be 55
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Passes parameter overrides, logging level and the 32-bit flag through to the seam' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Parameter @{ TargetPort = 1450 } -LoggingLevel 'Verbose' -Use32BitRuntime -Confirm:$false
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Parameter.TargetPort -eq 1450 -and $LoggingLevel -eq 'Verbose' -and $Use32BitRuntime.IsPresent
        }
    }

    It 'Resolves the named environment reference and passes it to the seam' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Confirm:$false
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Reference.Name -eq 'Prod'
        }
    }

    It 'Warns and does not start when the named environment reference is absent' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Missing' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'With -Synchronous, delegates to Wait-SsisExecution and returns the completed execution' {
        $result = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Synchronous -Confirm:$false
        $result.Status | Should -Be 'Success'
        Should -Invoke -CommandName Wait-SsisExecution -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not start' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -WhatIf
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not start when the package does not exist' {
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Missing.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Start-SsisExecution -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Disambiguates the environment reference by -EnvironmentFolder' {
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @(
                [PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' }
                [PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Shared' }
            )
        }

        $splatStart = @{
            SqlInstance       = 'TestInstance'
            Folder            = 'Finance'
            Project           = 'Sales'
            Package           = 'Load.dtsx'
            EnvironmentName   = 'Prod'
            EnvironmentFolder = 'Shared'
            Confirm           = $false
        }
        $null = Start-SsisExecution @splatStart

        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Reference.Name -eq 'Prod' -and $Reference.EnvironmentFolderName -eq 'Shared'
        }
    }

    It 'With -Use32BitRuntime alone, passes the flag and no parameter or logging set' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Use32BitRuntime -Confirm:$false
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Use32BitRuntime.IsPresent -and $null -eq $Parameter -and [string]::IsNullOrEmpty($LoggingLevel)
        }
    }

    It 'Warns and does not start when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not start when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Missing' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not start when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Missing' -Package 'Load.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Starts a piped package without reconnecting' {
            $package = [PSCustomObject]@{
                Name   = 'Load.dtsx'
                Parent = [PSCustomObject]@{
                    Name   = 'Sales'
                    Parent = [PSCustomObject]@{
                        Name   = 'Finance'
                        Parent = [PSCustomObject]@{ Name = 'SSISDB' }
                    }
                }
            }
            $package.PSObject.TypeNames.Insert(0, 'Ssis.Package')

            $null = $package | Start-SsisExecution -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
        }
    }
}
