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

    It 'Does not emit the value returned by DeployProject' {
        InModuleScope $script:moduleName {
            # The real CatalogFolder.DeployProject returns an Operation object; the wrapper declares
            # [OutputType([void])] and must not leak that return value into the pipeline (otherwise the
            # public Publish-SsisProject emits both the Operation and the project as an array).
            $folder = [PSCustomObject]@{}
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'DeployProject' -Value {
                param ($projectName, $projectStream)
                return 'fake-operation'
            }

            $result = Publish-SsisProjectObject -Folder $folder -Name 'Sales' -ProjectBytes ([byte[]](1, 2, 3))

            $result | Should -BeNullOrEmpty
        }
    }
}
