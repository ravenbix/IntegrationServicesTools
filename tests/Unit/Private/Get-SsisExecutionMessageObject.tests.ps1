BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionMessageObject' {
    It 'Returns the execution Messages collection' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ Messages = @('msg1', 'msg2') }
            $result = Get-SsisExecutionMessageObject -Execution $execution
            $result | Should -Be @('msg1', 'msg2')
        }
    }
}
