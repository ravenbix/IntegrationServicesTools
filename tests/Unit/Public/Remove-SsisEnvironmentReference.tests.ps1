BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = '.' })
        }
        Mock -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { }
    }

    Context 'ByInstance' {
        It 'Removes the matching reference' {
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Reference.Name -eq 'Prod' }
        }

        It 'Removes the matching absolute reference when -EnvironmentFolder is given' {
            Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
                @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Shared' })
            }
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -EnvironmentFolder 'Shared' -Confirm:$false
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Reference.EnvironmentFolderName -eq 'Shared'
            }
        }

        It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
            $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false

            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $SqlCredential.UserName -eq 'sa'
            }
        }

        It 'Errors and does not remove when no matching reference exists' {
            Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { @() }
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Errors and does not remove when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Errors and does not remove when the folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Nope' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Supports -WhatIf and does not remove' {
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -WhatIf
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }

    Context 'ByObject' {
        It 'Removes a piped reference via its parent project without connecting' {
            $reference = [PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = ''; Parent = [PSCustomObject]@{ Name = 'Sales' } }
            $reference.PSObject.TypeNames.Insert(0, 'Ssis.EnvironmentReference')

            $reference | Remove-SsisEnvironmentReference -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Reference.Name -eq 'Prod' -and $Project.Name -eq 'Sales'
            }
        }
    }
}
