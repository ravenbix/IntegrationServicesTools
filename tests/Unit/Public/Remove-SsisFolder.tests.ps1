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

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        Remove-SsisFolder -SqlInstance 'TestInstance' -SqlCredential $credential -Name 'Finance' -Confirm:$false

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Accepts the instance from the pipeline and drops the folder' {
        'TestInstance' | Remove-SsisFolder -Name 'Finance' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Errors and does not drop when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisFolder -SqlInstance 'TestInstance' -Name 'Finance' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisFolderObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
