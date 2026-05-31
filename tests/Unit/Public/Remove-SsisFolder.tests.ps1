BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisFolder' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Drops the folder when it exists (with -Confirm:$false)' {
        Remove-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Errors when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisFolder -SqlInstance 'TestInstance' -Name 'Nope' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not drop' {
        Remove-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -WhatIf
        Should -Invoke -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
