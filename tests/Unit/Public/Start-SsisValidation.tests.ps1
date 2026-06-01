BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisValidation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' })
        }
        Mock -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -MockWith { [long] 88 }
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 88; Status = 'Running' }
        } -ParameterFilter { $OperationId -eq 88 }
        Mock -CommandName Wait-SsisOperation -ModuleName $script:moduleName -MockWith {
            $obj = [PSCustomObject]@{ Id = 88; Status = 'Success' }
            $obj.PSObject.TypeNames.Insert(0, 'Ssis.Operation')
            $obj
        }
    }

    It 'Validates the project (no -Package) and returns the new Ssis.Operation' {
        $result = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Confirm:$false
        $result.Id | Should -Be 88
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Target.Name -eq 'Sales' -and $ReferenceUsage -eq 'UseAllReferences'
        }
    }

    It 'Validates a single package when -Package is supplied' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Target.Name -eq 'Load.dtsx'
        }
    }

    It 'Uses UseNoReference when -NoReference is given' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -NoReference -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ReferenceUsage -eq 'UseNoReference'
        }
    }

    It 'Resolves a named reference and uses SpecifyReference' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Prod' -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ReferenceUsage -eq 'SpecifyReference' -and $Reference.Name -eq 'Prod'
        }
    }

    It 'Disambiguates a named reference by -EnvironmentFolder' {
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @(
                [PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' }
                [PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Shared' }
            )
        }

        $splatEnvFolder = @{
            SqlInstance       = 'TestInstance'
            Folder            = 'Finance'
            Project           = 'Sales'
            EnvironmentName   = 'Prod'
            EnvironmentFolder = 'Shared'
            Confirm           = $false
        }
        $null = Start-SsisValidation @splatEnvFolder

        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ReferenceUsage -eq 'SpecifyReference' -and $Reference.EnvironmentFolderName -eq 'Shared'
        }
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $splatCred = @{
            SqlInstance   = 'TestInstance'
            SqlCredential = $credential
            Folder        = 'Finance'
            Project       = 'Sales'
            Confirm       = $false
        }
        $null = Start-SsisValidation @splatCred

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'With -Synchronous, forwards -PollInterval and -Timeout to Wait-SsisOperation' {
        $splatSync = @{
            SqlInstance  = 'TestInstance'
            Folder       = 'Finance'
            Project      = 'Sales'
            Synchronous  = $true
            PollInterval = 2
            Timeout      = 60
            Confirm      = $false
        }
        $null = Start-SsisValidation @splatSync

        Should -Invoke -CommandName Wait-SsisOperation -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $PollInterval -eq 2 -and $Timeout -eq 60
        }
    }

    It 'Throws when both -EnvironmentName and -NoReference are given' {
        { Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Prod' -NoReference -Confirm:$false } |
            Should -Throw
    }

    It 'Warns and does not validate when the named reference is absent' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Missing' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Passes the 32-bit flag through to the seam' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Use32BitRuntime -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Use32BitRuntime.IsPresent
        }
    }

    It 'With -Synchronous, delegates to Wait-SsisOperation and returns the completed operation' {
        $result = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Synchronous -Confirm:$false
        $result.Status | Should -Be 'Success'
        Should -Invoke -CommandName Wait-SsisOperation -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not validate' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -WhatIf
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not validate when the package does not exist' {
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Missing.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not validate when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Missing' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Validates a piped project without reconnecting (target is the project)' {
            $project = [PSCustomObject]@{
                Name   = 'Sales'
                Parent = [PSCustomObject]@{
                    Name   = 'Finance'
                    Parent = [PSCustomObject]@{ Name = 'SSISDB' }
                }
            }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $null = $project | Start-SsisValidation -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Target.Name -eq 'Sales'
            }
        }

        It 'Validates a piped package without reconnecting (target is the package)' {
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

            $null = $package | Start-SsisValidation -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Target.Name -eq 'Load.dtsx'
            }
        }
    }
}
