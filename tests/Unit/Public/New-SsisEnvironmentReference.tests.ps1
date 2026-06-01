BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { }
        # Empty before create; the created reference after create. Counter makes the second call return it.
        $script:refCalls = 0
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            $script:refCalls++
            if ($script:refCalls -ge 2) { @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = '.' }) }
            else { @() }
        }
    }

    It 'Creates a relative reference and returns it tagged Ssis.EnvironmentReference' {
        $script:refCalls = 0
        $result = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Environment -eq 'Prod' -and [string]::IsNullOrEmpty($EnvironmentFolder)
        }
    }

    It 'Passes -EnvironmentFolder through for an absolute reference' {
        $script:refCalls = 0
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -EnvironmentFolder 'Shared' -Confirm:$false
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $EnvironmentFolder -eq 'Shared' }
    }

    It 'Errors and does not create when the reference already exists' {
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = '.' }) }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Nope' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $script:refCalls = 0
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Supports -WhatIf and does not create' {
        $script:refCalls = 0
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -WhatIf
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Creates on a piped project without connecting' {
            $script:refCalls = 0
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $null = $project | New-SsisEnvironmentReference -Environment 'Prod' -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }

        It 'Creates an absolute reference on a piped project when -EnvironmentFolder is given' {
            $script:refCalls = 0
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $null = $project | New-SsisEnvironmentReference -Environment 'Prod' -EnvironmentFolder 'Shared' -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Project.Name -eq 'Sales' -and $EnvironmentFolder -eq 'Shared'
            }
        }
    }
}
