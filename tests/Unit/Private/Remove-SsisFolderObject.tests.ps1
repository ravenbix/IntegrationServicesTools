BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisFolderObject' {
    It 'Calls Drop on the supplied folder' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a Drop() ScriptMethod is a faithful stand-in for the MOM
            # CatalogFolder: the wrapper only calls Drop().
            $folder = [PSCustomObject]@{ DropCalled = $false }
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'Drop' -Value { $this.DropCalled = $true }

            Remove-SsisFolderObject -Folder $folder

            $folder.DropCalled | Should -BeTrue
        }
    }
}
