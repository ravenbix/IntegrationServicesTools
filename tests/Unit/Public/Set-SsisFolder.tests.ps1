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

    It 'Clears the description when an empty string is given' {
        $result = Set-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Description ''
        $result.Description | Should -Be ''
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq '' }
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Set-SsisFolder -SqlInstance 'TestInstance' -SqlCredential $credential -Name 'Finance' -Description 'new'

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Accepts the instance from the pipeline and updates the folder' {
        $result = 'TestInstance' | Set-SsisFolder -Name 'Finance' -Description 'new'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Folder'
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Errors and does not alter when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Description 'new' -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
