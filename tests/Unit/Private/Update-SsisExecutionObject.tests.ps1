BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Update-SsisExecutionObject' {
    It 'Calls Refresh on the execution and returns it' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ RefreshCalled = $false }
            $execution | Add-Member -MemberType 'ScriptMethod' -Name 'Refresh' -Value { $this.RefreshCalled = $true }

            $result = Update-SsisExecutionObject -Execution $execution

            $execution.RefreshCalled | Should -BeTrue
            $result | Should -Be $execution
        }
    }
}
