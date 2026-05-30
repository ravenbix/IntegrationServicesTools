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
