BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisFolder' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        Mock -CommandName New-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = $Name; Description = $Description } }
    }

    It 'Creates the folder and returns it tagged Ssis.Folder' {
        $result = New-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Description 'Finance'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Folder'
        $result.Name | Should -Be 'Finance'
        Should -Invoke -CommandName New-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Passes an empty description when none is supplied' {
        $null = New-SsisFolder -SqlInstance 'TestInstance' -Name 'Ops'
        Should -Invoke -CommandName New-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq '' }
    }

    It 'Errors and does not create when the folder already exists' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        $null = New-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not create' {
        $null = New-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -WhatIf
        Should -Invoke -CommandName New-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
