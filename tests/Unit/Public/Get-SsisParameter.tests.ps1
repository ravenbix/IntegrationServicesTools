BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisParameter' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith {
            # Check the $Name variable directly: inside a Pester mock body $PSBoundParameters does not
            # reliably reflect a splatted argument, but the parameter variable does.
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'TargetPort' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns project-level parameters tagged Ssis.Parameter' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Narrows to a single project parameter when -Name is given' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort'
            $result.Name | Should -Be 'TargetPort'
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'TargetPort' }
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Scopes to a package when -Package is given' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Load.dtsx' }
        }

        It 'Scopes to a single package parameter when -Package and -Name are given' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Name 'BatchSize'
            $result.Name | Should -Be 'BatchSize'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Load.dtsx' }
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Name -eq 'BatchSize' -and $Container.Name -eq 'Load.dtsx'
            }
        }

        It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
            $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

            $null = Get-SsisParameter -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales'

            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $SqlCredential.UserName -eq 'sa'
            }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Nope' -Project 'Sales' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the project does not exist' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the package does not exist' {
            Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Nope.dtsx' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }

    Context 'ByObject' {
        It 'Lists parameters of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisParameter
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Container.Name -eq 'Sales' }
        }

        It 'Narrows to a single parameter on a piped container when -Name is given' {
            $package = [PSCustomObject]@{ Name = 'Load.dtsx' }
            $package.PSObject.TypeNames.Insert(0, 'Ssis.Package')

            $result = $package | Get-SsisParameter -Name 'BatchSize'
            $result.Name | Should -Be 'BatchSize'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Container.Name -eq 'Load.dtsx' -and $Name -eq 'BatchSize'
            }
        }
    }
}
