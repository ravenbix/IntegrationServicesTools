BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Port'; Value = 1433 } }
    }

    It 'Infers the type code from the value and returns an Ssis.EnvironmentVariable' {
        $result = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1433 -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Name -eq 'Port' -and $Value -eq 1433 -and $TypeCode -eq [System.TypeCode]::Int32 -and $Sensitive -eq $false
        }
    }

    It 'Honors an explicit -DataType override' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value '1433' -DataType 'Int32' -Confirm:$false
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $TypeCode -eq [System.TypeCode]::Int32 }
    }

    It 'Passes -Sensitive through to the interop wrapper' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Password' -Value 'secret' -Sensitive -Confirm:$false
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Sensitive -eq $true }
    }

    It 'Forwards the description to the interop wrapper' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1 -Description 'db port' -Confirm:$false
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Description -eq 'db port' }
    }

    It 'Warns and does not set when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Nope' -Environment 'Prod' -Name 'Port' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the environment does not exist' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Nope' -Name 'Port' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not set' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1 -WhatIf
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Forwards the SqlCredential to Connect-SsisCatalog' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p' -AsPlainText -Force))
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1 -SqlCredential $credential -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $null -ne $SqlCredential }
    }

    Context 'ByObject' {
        It 'Sets on a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $null = $environment | Set-SsisEnvironmentVariable -Name 'Port' -Value 1433 -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }
    }
}
