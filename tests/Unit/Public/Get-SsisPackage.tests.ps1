BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisPackage' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }) }
        }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'P1' }) }
        }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'Load.dtsx' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns packages tagged Ssis.Package for a folder and project' {
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Package'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns when a named package is not found' {
            Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -Name 'Missing.dtsx' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Enumerates packages across all folders and projects when scopes are omitted' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
                @([PSCustomObject]@{ Name = 'F1' }, [PSCustomObject]@{ Name = 'F2' })
            }

            $result = Get-SsisPackage -SqlInstance 'TestInstance'

            ($result | Measure-Object).Count | Should -Be 2
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 2 -Scope It
        }

        It 'Warns and returns nothing when the named folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -Folder 'Nope' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Forwards the SqlCredential to Connect-SsisCatalog' {
            $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
            $null = Get-SsisPackage -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -SqlCredential $cred
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
        }
    }

    Context 'ByObject' {
        It 'Lists packages of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisPackage
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Package'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }
    }
}
