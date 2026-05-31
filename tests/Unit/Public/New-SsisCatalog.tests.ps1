BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisCatalog' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        Mock -CommandName New-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        # Created in BeforeAll (not the Describe body) so it is in scope during the run phase;
        # variables assigned directly in the Describe block only exist during Pester discovery.
        $cred = [System.Management.Automation.PSCredential]::new('x', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
    }

    It 'Creates the catalog and returns it tagged Ssis.Catalog' {
        $result = New-SsisCatalog -SqlInstance 'TestInstance' -CatalogPassword $cred
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Catalog'
        Should -Invoke -CommandName New-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Does not create when the catalog already exists, and writes an error' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        $result = New-SsisCatalog -SqlInstance 'TestInstance' -CatalogPassword $cred -ErrorAction SilentlyContinue -ErrorVariable err
        $result | Should -BeNullOrEmpty
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not create' {
        $null = New-SsisCatalog -SqlInstance 'TestInstance' -CatalogPassword $cred -WhatIf
        Should -Invoke -CommandName New-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
