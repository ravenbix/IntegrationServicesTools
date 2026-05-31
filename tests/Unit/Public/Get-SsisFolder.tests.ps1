BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisFolder' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            # Check the $Name variable directly: inside a Pester mock body $PSBoundParameters does
            # not reliably reflect a splatted argument, but the parameter variable does.
            if ($Name) { [PSCustomObject]@{ Name = $Name; Description = 'one' } }
            else { @([PSCustomObject]@{ Name = 'A'; Description = 'a' }, [PSCustomObject]@{ Name = 'B'; Description = 'b' }) }
        }
    }

    It 'Returns all folders tagged Ssis.Folder when no name is given' {
        $result = Get-SsisFolder -SqlInstance 'TestInstance'
        ($result | Measure-Object).Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'Ssis.Folder'
    }

    It 'Returns a single folder when -Name is given' {
        $result = Get-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance'
        ($result | Measure-Object).Count | Should -Be 1
        $result.Name | Should -Be 'Finance'
        Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Finance' }
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisFolder -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }
}
