BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Port' } }
        Mock -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { }
    }

    Context 'ByInstance' {
        It 'Removes the variable' {
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Confirm:$false
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Port' }
        }

        It 'Errors and does not remove when the variable does not exist' {
            Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Errors and does not remove when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Errors and does not remove when the folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Nope' -Environment 'Prod' -Name 'Port' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Errors and does not remove when the environment does not exist' {
            Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Nope' -Name 'Port' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Supports -WhatIf and does not remove' {
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -WhatIf
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }

    Context 'ByObject' {
        It 'Removes a piped variable via its parent environment without connecting' {
            $variable = [PSCustomObject]@{ Name = 'Port'; Parent = [PSCustomObject]@{ Name = 'Prod' } }
            $variable.PSObject.TypeNames.Insert(0, 'Ssis.EnvironmentVariable')

            $variable | Remove-SsisEnvironmentVariable -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Name -eq 'Port' -and $Environment.Name -eq 'Prod'
            }
        }
    }
}
