BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Stop-SsisExecutionObject' {
    It 'Calls Stop on the execution' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ StopCalled = $false }
            $execution | Add-Member -MemberType 'ScriptMethod' -Name 'Stop' -Value { $this.StopCalled = $true }

            Stop-SsisExecutionObject -Execution $execution

            $execution.StopCalled | Should -BeTrue
        }
    }
}
