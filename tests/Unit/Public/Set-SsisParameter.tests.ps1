BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisParameter' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'TargetPort'; DefaultValue = 1450 } }
        Mock -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Sets a literal value and returns Ssis.Parameter' {
        $result = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1450 -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Literal' -and $Value -eq 1450
        }
    }

    It 'Sets a referenced value with the variable name' {
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -ReferencedVariable 'Port' -Confirm:$false
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Referenced' -and $Value -eq 'Port'
        }
    }

    It 'Sets a package-level parameter when -Package is given' {
        $result = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Name 'BatchSize' -Value 500 -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
        Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Load.dtsx' }
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Literal' -and $Value -eq 500
        }
    }

    It 'Sets a literal null value when -Value is $null' {
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value $null -Confirm:$false
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Literal' -and $null -eq $Value
        }
    }

    It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
        $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

        $null = Set-SsisParameter -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1450 -Confirm:$false

        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Throws when both -Value and -ReferencedVariable are supplied' {
        { Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1 -ReferencedVariable 'Port' -Confirm:$false } |
            Should -Throw
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Throws when neither -Value nor -ReferencedVariable is supplied' {
        { Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Confirm:$false } |
            Should -Throw
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the parameter does not exist' {
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'Missing' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Nope' -Project 'Sales' -Name 'TargetPort' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the package does not exist' {
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Nope.dtsx' -Name 'TargetPort' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not set' {
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1 -WhatIf
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Sets a piped parameter via its owning project without connecting' {
            $parameter = [PSCustomObject]@{ Name = 'TargetPort'; Parent = [PSCustomObject]@{ Name = 'Sales' } }
            $parameter.PSObject.TypeNames.Insert(0, 'Ssis.Parameter')

            $null = $parameter | Set-SsisParameter -Value 1450 -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Parameter.Name -eq 'TargetPort' -and $Project.Name -eq 'Sales'
            }
        }

        It 'Binds a piped parameter to an environment variable with -ReferencedVariable' {
            $parameter = [PSCustomObject]@{ Name = 'TargetPort'; Parent = [PSCustomObject]@{ Name = 'Sales' } }
            $parameter.PSObject.TypeNames.Insert(0, 'Ssis.Parameter')

            $null = $parameter | Set-SsisParameter -ReferencedVariable 'Port' -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $ValueType -eq 'Referenced' -and $Value -eq 'Port'
            }
        }
    }
}
