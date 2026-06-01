BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisPackageObject' {
    It 'Returns the named package when it exists' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{ Name = 'Load.dtsx' }
            $project = [PSCustomObject]@{ Packages = @{ 'Load.dtsx' = $package } }

            $result = Get-SsisPackageObject -Project $project -Name 'Load.dtsx'

            $result.Name | Should -Be 'Load.dtsx'
        }
    }

    It 'Returns $null when the named package does not exist' {
        InModuleScope $script:moduleName {
            $project = [PSCustomObject]@{ Packages = @{} }

            $result = Get-SsisPackageObject -Project $project -Name 'Missing.dtsx'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Packages collection when no name is given' {
        InModuleScope $script:moduleName {
            $project = [PSCustomObject]@{
                Packages = @{
                    'A.dtsx' = [PSCustomObject]@{ Name = 'A.dtsx' }
                    'B.dtsx' = [PSCustomObject]@{ Name = 'B.dtsx' }
                }
            }

            $result = Get-SsisPackageObject -Project $project

            $result.Count | Should -Be 2
        }
    }
}
