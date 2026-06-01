BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Export-SsisProjectObject' {
    It 'Returns the bytes from the project GetProjectBytes call' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a GetProjectBytes() ScriptMethod is a faithful stand-in for the
            # MOM ProjectInfo: the wrapper only calls GetProjectBytes() and returns its result.
            $project = [PSCustomObject]@{}
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'GetProjectBytes' -Value {
                return [byte[]](9, 8, 7)
            }

            $result = Export-SsisProjectObject -Project $project

            $result | Should -Be ([byte[]](9, 8, 7))
        }
    }
}
