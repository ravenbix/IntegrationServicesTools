BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Removes the environment' {
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Errors and does not remove when the environment does not exist' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not remove when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not remove when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Nope' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not remove' {
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -WhatIf
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Name 'Prod' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
    }

    Context 'ByObject' {
        It 'Removes a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $environment | Remove-SsisEnvironment -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }

        It 'Does not remove a piped environment under -WhatIf' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $environment | Remove-SsisEnvironment -WhatIf
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }
}
