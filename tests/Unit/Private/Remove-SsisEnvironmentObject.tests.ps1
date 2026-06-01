BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentObject' {
    It 'Calls Drop on the supplied environment' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a Drop() ScriptMethod is a faithful stand-in for the MOM
            # EnvironmentInfo: the wrapper only calls Drop().
            $environment = [PSCustomObject]@{ DropCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Drop' -Value { $this.DropCalled = $true }

            Remove-SsisEnvironmentObject -Environment $environment

            $environment.DropCalled | Should -BeTrue
        }
    }
}
