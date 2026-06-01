BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentReferenceObject' {
    It 'Returns the project References collection' {
        InModuleScope $script:moduleName {
            $references = @(
                [PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' }
                [PSCustomObject]@{ EnvironmentName = 'Dev'; EnvironmentFolderName = 'Shared' }
            )
            $project = [PSCustomObject]@{ References = $references }

            $result = Get-SsisEnvironmentReferenceObject -Project $project

            ($result | Measure-Object).Count | Should -Be 2
        }
    }
}
