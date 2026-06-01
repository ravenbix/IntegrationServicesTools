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
            $message1 = [PSCustomObject]@{ Id = 1; Message = 'Start' }
            $message2 = [PSCustomObject]@{ Id = 2; Message = 'Done' }
            $execution = [PSCustomObject]@{ Messages = @($message1, $message2) }

            $result = Get-SsisExecutionMessageObject -Execution $execution
            $result | Should -HaveCount 2
            $result[0].Message | Should -Be 'Start'
            $result[1].Message | Should -Be 'Done'
        }
    }

    It 'Returns an empty collection (not null) when the execution has no messages' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ Messages = @() }

            $result = Get-SsisExecutionMessageObject -Execution $execution
            $result | Should -HaveCount 0
        }
    }
}
