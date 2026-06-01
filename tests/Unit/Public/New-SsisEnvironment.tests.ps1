BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        Mock -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = $Name } }
    }

    It 'Creates the environment and returns an Ssis.Environment' {
        $result = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
    }

    It 'Errors and does not create when the environment already exists' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Nope' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not create' {
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -WhatIf
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Forwards the description to New-SsisEnvironmentObject' {
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Description 'Production env' -Confirm:$false
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq 'Production env' }
    }

    It 'Defaults the description to an empty string when -Description is omitted' {
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq '' }
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Name 'Prod' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
    }

    Context 'ByObject' {
        It 'Creates in a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | New-SsisEnvironment -Name 'Prod' -Confirm:$false
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }

        It 'Creates in a piped folder with a description without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | New-SsisEnvironment -Name 'Prod' -Description 'Production env' -Confirm:$false
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq 'Production env' }
        }

        It 'Does not create a piped-folder environment under -WhatIf' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $null = $folder | New-SsisEnvironment -Name 'Prod' -WhatIf
            Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }
}
