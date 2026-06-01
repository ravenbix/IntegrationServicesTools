BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentVariableObject' {
    It 'Removes the named variable and alters the environment' {
        InModuleScope $script:moduleName {
            $variables = [PSCustomObject]@{ Removed = $null }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Remove' -Value { param ($name) $this.Removed = $name }

            $environment = [PSCustomObject]@{ Variables = $variables; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Remove-SsisEnvironmentVariableObject -Environment $environment -Name 'Port'

            $environment.Variables.Removed | Should -Be 'Port'
            $environment.AlterCalled | Should -BeTrue
        }
    }
}
