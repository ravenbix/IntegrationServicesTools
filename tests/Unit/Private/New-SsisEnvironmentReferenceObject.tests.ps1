BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentReferenceObject' {
    It 'Adds a relative reference (no folder) and alters the project' {
        InModuleScope $script:moduleName {
            $references = [PSCustomObject]@{ AddedEnv = $null; AddedFolder = 'unset' }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($environmentName, $environmentFolderName)
                $this.AddedEnv = $environmentName
                $this.AddedFolder = $environmentFolderName
            }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod'

            $project.References.AddedEnv | Should -Be 'Prod'
            $project.References.AddedFolder | Should -BeNullOrEmpty
            $project.AlterCalled | Should -BeTrue
        }
    }

    It 'Adds an absolute reference with a folder and alters the project' {
        InModuleScope $script:moduleName {
            $references = [PSCustomObject]@{ AddedEnv = $null; AddedFolder = $null }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($environmentName, $environmentFolderName)
                $this.AddedEnv = $environmentName
                $this.AddedFolder = $environmentFolderName
            }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod' -EnvironmentFolder 'Shared'

            $project.References.AddedEnv | Should -Be 'Prod'
            $project.References.AddedFolder | Should -Be 'Shared'
            $project.AlterCalled | Should -BeTrue
        }
    }
}
