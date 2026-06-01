BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        # Three executions spanning two packages and two statuses.
        $script:allExecutions = @(
            [PSCustomObject]@{ Id = 1; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
            [PSCustomObject]@{ Id = 2; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Success' }
            [PSCustomObject]@{ Id = 3; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Other.dtsx'; Status = 'Running' }
        )
    }

    It 'Returns a single execution by id, decorated as Ssis.Execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
        } -ParameterFilter { $ExecutionId -eq 42 }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 42
        $result.Id | Should -Be 42
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
    }

    It 'Returns every execution when no filter is given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $result = Get-SsisExecution -SqlInstance 'TestInstance'
        ($result | Measure-Object).Count | Should -Be 3
        $result[0].PSObject.TypeNames | Should -Contain 'Ssis.Execution'
    }

    It 'Warns and returns nothing when the execution id is not found' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null } -ParameterFilter { $ExecutionId -eq 999 }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 999 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Get-SsisExecution -SqlInstance 'TestInstance' -SqlCredential $credential -Status 'Running'

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Filters by folder name when -Folder is given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            @(
                [PSCustomObject]@{ Id = 1; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
                [PSCustomObject]@{ Id = 4; FolderName = 'HR'; ProjectName = 'Payroll'; PackageName = 'Run.dtsx'; Status = 'Running' }
            )
        }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance'
        ($result | Measure-Object).Count | Should -Be 1
        $result.FolderName | Should -Be 'Finance'
    }

    It 'Filters by project name when -Project is given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            @(
                [PSCustomObject]@{ Id = 1; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
                [PSCustomObject]@{ Id = 5; FolderName = 'Finance'; ProjectName = 'Accounting'; PackageName = 'Close.dtsx'; Status = 'Running' }
            )
        }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Project 'Sales'
        ($result | Measure-Object).Count | Should -Be 1
        $result.ProjectName | Should -Be 'Sales'
    }

    It 'Combines folder, project, package and status filters' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $splatExecution = @{
            SqlInstance = 'TestInstance'
            Folder      = 'Finance'
            Project     = 'Sales'
            Package     = 'Load.dtsx'
            Status      = 'Success'
        }
        $result = Get-SsisExecution @splatExecution
        ($result | Measure-Object).Count | Should -Be 1
        $result.Id | Should -Be 2
        $result.Status | Should -Be 'Success'
    }

    It 'Filters by package name when -Package is given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'
        ($result | Measure-Object).Count | Should -Be 2
        $result.PackageName | Should -Not -Contain 'Other.dtsx'
    }

    It 'Filters by -Status' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Status 'Running'
        ($result | Measure-Object).Count | Should -Be 2
        $result.Status | Should -Not -Contain 'Success'
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecution -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Lists the executions of a piped package without reconnecting' {
            Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

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

            $result = $package | Get-SsisExecution
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 2
            $result.PackageName | Should -Not -Contain 'Other.dtsx'
        }

        It 'Applies -Status when listing the executions of a piped package' {
            Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

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

            $result = $package | Get-SsisExecution -Status 'Running'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 1
            $result.Status | Should -Be 'Running'
            $result.PackageName | Should -Be 'Load.dtsx'
        }
    }
}
