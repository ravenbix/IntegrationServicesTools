BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentReferenceObject' {
    It 'Removes the supplied reference and alters the project' {
        InModuleScope $script:moduleName {
            $reference = [PSCustomObject]@{ Name = 'Prod' }

            $references = [PSCustomObject]@{ Removed = $null }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Remove' -Value { param ($item) $this.Removed = $item }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Remove-SsisEnvironmentReferenceObject -Project $project -Reference $reference

            $project.References.Removed.Name | Should -Be 'Prod'
            $project.AlterCalled | Should -BeTrue
        }
    }
}
