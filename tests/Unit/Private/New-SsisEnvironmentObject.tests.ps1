BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentObject' {
    It 'Throws when constructing against a non-MOM folder (reaches the constructor)' {
        InModuleScope $script:moduleName {
            # The wrapper constructs a real EnvironmentInfo from the folder; a plain object is not a
            # CatalogFolder, so the typed constructor rejects it. This proves the wrapper calls the
            # constructor rather than silently succeeding. Real construction is covered by integration.
            $folder = [PSCustomObject]@{ Name = 'Finance' }

            { New-SsisEnvironmentObject -Folder $folder -Name 'Prod' -Description '' } | Should -Throw
        }
    }
}
