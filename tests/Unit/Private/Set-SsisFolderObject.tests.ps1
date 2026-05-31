BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisFolderObject' {
    It 'Assigns the description, calls Alter and returns the folder' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a settable Description and an Alter() ScriptMethod is a faithful
            # stand-in for the MOM CatalogFolder: the wrapper only sets Description and calls Alter().
            $folder = [PSCustomObject]@{
                Description = 'old'
                AlterCalled = $false
            }
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            $result = Set-SsisFolderObject -Folder $folder -Description 'new'

            $result.Description | Should -Be 'new'
            $result.AlterCalled | Should -BeTrue
        }
    }

    It 'Accepts an empty description' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{ Description = 'old' }
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { }

            $result = Set-SsisFolderObject -Folder $folder -Description ''

            $result.Description | Should -Be ''
        }
    }
}
