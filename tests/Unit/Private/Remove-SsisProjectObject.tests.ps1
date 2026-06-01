BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisProjectObject' {
    It 'Calls Drop on the supplied project' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a Drop() ScriptMethod is a faithful stand-in for the MOM
            # ProjectInfo: the wrapper only calls Drop().
            $project = [PSCustomObject]@{ DropCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Drop' -Value { $this.DropCalled = $true }

            Remove-SsisProjectObject -Project $project

            $project.DropCalled | Should -BeTrue
        }
    }
}
