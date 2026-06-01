BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Publish-SsisProjectObject' {
    It 'Calls DeployProject with the name and bytes on the supplied folder' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a DeployProject() ScriptMethod is a faithful stand-in for the MOM
            # CatalogFolder: the wrapper only calls DeployProject(name, bytes).
            $folder = [PSCustomObject]@{ DeployedName = $null; DeployedBytes = $null }
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'DeployProject' -Value {
                param ($projectName, $projectStream)
                $this.DeployedName = $projectName
                $this.DeployedBytes = $projectStream
            }

            $bytes = [byte[]](1, 2, 3)
            Publish-SsisProjectObject -Folder $folder -Name 'Sales' -ProjectBytes $bytes

            $folder.DeployedName | Should -Be 'Sales'
            $folder.DeployedBytes | Should -Be $bytes
        }
    }
}
