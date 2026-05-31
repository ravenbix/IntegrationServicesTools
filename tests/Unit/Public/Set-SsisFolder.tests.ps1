BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisFolder' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance'; Description = 'old' } }
        Mock -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance'; Description = $Description } }
    }

    It 'Updates the description and returns the folder tagged Ssis.Folder' {
        $result = Set-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Description 'new'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Folder'
        $result.Description | Should -Be 'new'
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq 'new' }
    }

    It 'Errors when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisFolder -SqlInstance 'TestInstance' -Name 'Nope' -Description 'x' -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not alter' {
        $null = Set-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Description 'new' -WhatIf
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
