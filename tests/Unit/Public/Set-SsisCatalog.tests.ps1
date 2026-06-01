BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisCatalog' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
    }

    It 'Passes only the supplied properties to the interop wrapper' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property.ContainsKey('MaxProjectVersions') -and $Property['MaxProjectVersions'] -eq 5 -and -not $Property.ContainsKey('OperationCleanupEnabled')
        }
    }

    It 'Writes an error when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5 -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not alter' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5 -WhatIf
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Forwards -SqlCredential to Connect-SsisCatalog when given' {
        $cred = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString 'p@ss' -AsPlainText -Force))
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -SqlCredential $cred -RetentionDays 90
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $SqlCredential.UserName -eq 'sa'
        }
    }

    It 'Maps -RetentionDays to the OperationLogRetentionTime property' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -RetentionDays 365
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property.ContainsKey('OperationLogRetentionTime') -and $Property['OperationLogRetentionTime'] -eq 365 -and -not $Property.ContainsKey('RetentionDays')
        }
    }

    It 'Passes -EncryptionAlgorithm through to the interop wrapper' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -EncryptionAlgorithm 'AES_256'
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property.ContainsKey('EncryptionAlgorithm') -and $Property['EncryptionAlgorithm'] -eq 'AES_256'
        }
    }

    It 'Passes the boolean cleanup toggles through to the interop wrapper' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -OperationCleanupEnabled $true -VersionCleanupEnabled $false
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property['OperationCleanupEnabled'] -eq $true -and $Property['VersionCleanupEnabled'] -eq $false
        }
    }

    It 'Passes every supplied property in a single call' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -MaxProjectVersions 5 -RetentionDays 365
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Property['MaxProjectVersions'] -eq 5 -and $Property['OperationLogRetentionTime'] -eq 365
        }
    }

    It 'Warns and does not alter when no properties are supplied' {
        $null = Set-SsisCatalog -SqlInstance 'TestInstance' -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Accepts the instance from the pipeline' {
        $result = 'TestInstance' | Set-SsisCatalog -MaxProjectVersions 5
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Catalog'
        Should -Invoke -CommandName Set-SsisCatalogObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }
}
