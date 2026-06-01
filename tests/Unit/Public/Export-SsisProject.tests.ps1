BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Export-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Export-SsisProjectObject -ModuleName $script:moduleName -MockWith { [byte[]](1, 2, 3) }
        Mock -CommandName Set-Content -ModuleName $script:moduleName -MockWith { }
        # Directory exists; target file does not (no overwrite needed) by default.
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Container' }
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $false } -ParameterFilter { $PathType -eq 'Leaf' }
    }

    It 'Writes <project>.ispac into the directory and returns its FileInfo' {
        $result = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Confirm:$false
        $result.Name | Should -Be 'Sales.ispac'
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Path -like '*Sales.ispac' }
    }

    It 'Errors and does not write when the file exists without -Force' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Overwrites an existing file when -Force is given' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Force -Confirm:$false
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not write' {
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -WhatIf
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Exports a piped Ssis.Project without connecting' {
        $project = [PSCustomObject]@{ Name = 'Sales' }
        $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

        $null = $project | Export-SsisProject -Path 'C:\out' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Export-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog' {
        $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -SqlCredential $cred -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
    }

    It 'Errors and does not write when the output directory does not exist' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $false } -ParameterFilter { $PathType -eq 'Container' }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Nope' -Name 'Sales' -Path 'C:\out' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Nope' -Path 'C:\out' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
