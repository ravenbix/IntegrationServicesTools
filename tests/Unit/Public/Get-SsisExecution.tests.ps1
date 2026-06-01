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
    }
}
