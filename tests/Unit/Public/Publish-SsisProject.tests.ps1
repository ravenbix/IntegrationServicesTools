BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Publish-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true }
        Mock -CommandName Get-Content -ModuleName $script:moduleName -MockWith { [byte[]](1, 2, 3) }
    }

    It 'Deploys with the name defaulted from the file and returns Ssis.Project' {
        $result = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Name -eq 'Sales' -and $ProjectBytes.Count -eq 3
        }
    }

    It 'Uses -Name to override the project name' {
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -Name 'Renamed' -Confirm:$false
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Renamed' }
    }

    It 'Errors and does not deploy when the .ispac path is missing' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $false }
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Missing.ispac' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not deploy when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Nope' -Path 'C:\out\Sales.ispac' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not deploy' {
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -WhatIf
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog' {
        $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -SqlCredential $cred -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $SqlCredential.UserName -eq 'sa' }
    }

    It 'Errors and does not deploy when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Deploys into a piped Ssis.Folder without connecting' {
        $folder = [PSCustomObject]@{ Name = 'Finance' }
        $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

        $null = $folder | Publish-SsisProject -Path 'C:\out\Sales.ispac' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' -and $Name -eq 'Sales' }
    }

    It 'Uses -Name to override the project name when deploying into a piped folder (ByObject + Name)' {
        $folder = [PSCustomObject]@{ Name = 'Finance' }
        $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

        $null = $folder | Publish-SsisProject -Path 'C:\out\Sales.ispac' -Name 'Renamed' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' -and $Name -eq 'Renamed' }
    }

    It 'Supports -WhatIf for a piped folder and does not deploy (ByObject + WhatIf)' {
        $folder = [PSCustomObject]@{ Name = 'Finance' }
        $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

        $null = $folder | Publish-SsisProject -Path 'C:\out\Sales.ispac' -WhatIf
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
