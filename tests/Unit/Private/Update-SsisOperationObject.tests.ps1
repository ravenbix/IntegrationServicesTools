BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Update-SsisOperationObject' {
    It 'Calls Refresh on the operation and returns it' {
        InModuleScope $script:moduleName {
            $operation = [PSCustomObject]@{ RefreshCalled = $false }
            $operation | Add-Member -MemberType 'ScriptMethod' -Name 'Refresh' -Value { $this.RefreshCalled = $true }

            $result = Update-SsisOperationObject -Operation $operation

            $operation.RefreshCalled | Should -BeTrue
            $result | Should -Be $operation
        }
    }
}
