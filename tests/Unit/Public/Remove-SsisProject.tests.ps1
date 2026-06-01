BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Drops the project when it exists (with -Confirm:$false)' {
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Errors when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Nope' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not drop' {
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -WhatIf
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Drops a piped Ssis.Project without connecting' {
        $project = [PSCustomObject]@{ Name = 'Sales' }
        $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

        $project | Remove-SsisProject -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog' {
        $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -SqlCredential $cred -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
    }

    It 'Errors when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Nope' -Name 'Sales' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
