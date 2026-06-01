BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith {
            if ($Name) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'ConnString' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns variables tagged Ssis.EnvironmentVariable for a folder and environment' {
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
        }

        It 'Returns a single variable when -Name is given' {
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'ConnString'
            $result.Name | Should -Be 'ConnString'
        }

        It 'Warns and returns nothing when the environment does not exist' {
            Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Nope' -Environment 'Prod' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Warns when a named variable is not found' {
            Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { $null }
            Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Missing' -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Forwards the SqlCredential to Connect-SsisCatalog' {
            $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p' -AsPlainText -Force))
            Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -SqlCredential $credential | Out-Null
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $null -ne $SqlCredential }
        }
    }

    Context 'ByObject' {
        It 'Lists variables of a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $result = $environment | Get-SsisEnvironmentVariable
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }
    }
}
