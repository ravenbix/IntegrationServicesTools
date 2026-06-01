BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }, [PSCustomObject]@{ Name = 'F2' }) }
        }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'P1' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns folder-scoped projects tagged Ssis.Project' {
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
            Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Finance' }
        }

        It 'Enumerates every folder when -Folder is omitted' {
            $result = Get-SsisProject -SqlInstance 'TestInstance'
            ($result | Measure-Object).Count | Should -Be 2
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 2 -Scope It
        }

        It 'Returns a single project when -Folder and -Name are given' {
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales'
            $result.Name | Should -Be 'Sales'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Searches every folder for a named project when -Name is given without -Folder' {
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Name 'Sales'
            # -Folder omitted: every folder (F1, F2) is enumerated, each queried by project name, so
            # the named project is returned once per folder that contains it.
            ($result | Measure-Object).Count | Should -Be 2
            $result[0].Name | Should -Be 'Sales'
            Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { -not $Name }
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 2 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisProject -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns when a named project is not found' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Name 'Missing' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the named folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Nope' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Forwards the SqlCredential to Connect-SsisCatalog' {
            $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
            $null = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -SqlCredential $cred
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
        }
    }

    Context 'ByObject' {
        It 'Lists projects of a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisProject
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }

        It 'Returns a single named project from a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisProject -Name 'Sales'
            $result.Name | Should -Be 'Sales'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns when a named project is not found in a piped folder' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisProject -Name 'Missing' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }
    }
}
