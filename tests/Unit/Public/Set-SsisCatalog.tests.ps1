BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisCatalog' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
    }

    It 'Passes only the supplied properties to the interop wrapper' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property.ContainsKey('MaxProjectVersions') -and $Property['MaxProjectVersions'] -eq 5 -and -not $Property.ContainsKey('OperationCleanupEnabled')
        }
    }

    It 'Writes an error when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5 -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not alter' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5 -WhatIf
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
