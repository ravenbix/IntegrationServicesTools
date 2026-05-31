BeforeDiscovery {
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
    $script:instance = $env:SSIS_TEST_INSTANCE
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisCatalog (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Returns an Ssis.Catalog object from a real instance' {
        $catalog = Get-SsisCatalog -SqlInstance $script:instance
        $catalog.PSObject.TypeNames | Should -Contain 'Ssis.Catalog'
        $catalog.Name | Should -Be 'SSISDB'
    }
}

Describe 'New-SsisCatalog (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Errors when the catalog already exists (does not recreate SSISDB)' {
        $securePassword = ConvertTo-SecureString -String 'P@ssw0rd-Integration!' -AsPlainText -Force
        $catalogPassword = [System.Management.Automation.PSCredential]::new('ignored', $securePassword)

        New-SsisCatalog -SqlInstance $script:instance -CatalogPassword $catalogPassword -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable createError | Out-Null

        $createError | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-SsisCatalog (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    BeforeAll {
        # Capture the current value so the test can restore it afterwards.
        $script:originalMaxProjectVersions = (Get-SsisCatalog -SqlInstance $script:instance).MaxProjectVersions
    }

    AfterAll {
        if ($null -ne $script:originalMaxProjectVersions)
        {
            Set-SsisCatalog -SqlInstance $script:instance -MaxProjectVersions $script:originalMaxProjectVersions -Confirm:$false | Out-Null
        }
    }

    It 'Updates a catalog property and persists it' {
        $newValue = [int] $script:originalMaxProjectVersions + 1

        Set-SsisCatalog -SqlInstance $script:instance -MaxProjectVersions $newValue -Confirm:$false | Out-Null

        (Get-SsisCatalog -SqlInstance $script:instance).MaxProjectVersions | Should -Be $newValue
    }
}
