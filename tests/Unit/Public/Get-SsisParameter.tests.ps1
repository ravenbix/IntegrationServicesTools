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
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'TargetPort' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns project-level parameters tagged Ssis.Parameter' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Scopes to a package when -Package is given' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Load.dtsx' }
        }

        It 'Warns and returns nothing when the project does not exist' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
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
    }
}
