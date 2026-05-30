BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisCatalog' {
    Context 'When the catalog exists' {
        BeforeAll {
            Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        }

        It 'Returns one object tagged Ssis.Catalog' {
            $result = Get-SsisCatalog -SqlInstance 'TestInstance'
            ($result | Measure-Object).Count | Should -Be 1
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Catalog'
            $result.Name | Should -Be 'SSISDB'
        }

        It 'Connects exactly once' {
            $null = Get-SsisCatalog -SqlInstance 'TestInstance'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
        }

        It 'Forwards the credential to Connect-SsisCatalog' {
            $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
            $null = Get-SsisCatalog -SqlInstance 'TestInstance' -SqlCredential $cred
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -ParameterFilter { $SqlCredential.UserName -eq 'sa' } -Times 1 -Scope It
        }
    }

    Context 'When the catalog does not exist' {
        BeforeAll {
            Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{} }
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        }

        It 'Writes a warning and returns nothing' {
            $result = Get-SsisCatalog -SqlInstance 'TestInstance' -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }
    }
}
