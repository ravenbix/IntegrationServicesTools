BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }, [PSCustomObject]@{ Name = 'F2' }) }
        }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'E1' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns folder-scoped environments tagged Ssis.Environment' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Finance' }
        }

        It 'Enumerates every folder when -Folder is omitted' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance'
            ($result | Measure-Object).Count | Should -Be 2
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 2 -Scope It
        }

        It 'Returns a single environment when -Folder and -Name are given' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod'
            $result.Name | Should -Be 'Prod'
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns when a named environment is not found' {
            Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
            Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Missing' -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the named folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Nope' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Forwards the SqlCredential to Connect-SsisCatalog' {
            $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -SqlCredential $credential | Out-Null
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $null -ne $SqlCredential }
        }
    }

    Context 'ByObject' {
        It 'Lists environments of a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisEnvironment
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }
    }
}
