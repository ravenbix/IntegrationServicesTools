BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisFolderObject' {
    # This wrapper constructs a CatalogFolder via [Type]::new() and calls Create(), which eagerly
    # opens a SQL connection - it cannot run without a live server. Its real behaviour is covered
    # by the Integration tests; here we only assert its parameter contract.
    It 'Exists and exposes the -Catalog, -Name and -Description parameters' {
        InModuleScope $script:moduleName {
            $command = Get-Command -Name 'New-SsisFolderObject'

            $command | Should -Not -BeNullOrEmpty
            $command.Parameters.Keys | Should -Contain 'Catalog'
            $command.Parameters.Keys | Should -Contain 'Name'
            $command.Parameters.Keys | Should -Contain 'Description'
        }
    }
}
