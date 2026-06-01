BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = '' })
        }
    }

    Context 'ByInstance' {
        It 'Returns references tagged Ssis.EnvironmentReference for a folder and project' {
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Passes -SqlCredential through to Connect-SsisCatalog when given' {
            $credential = [System.Management.Automation.PSCredential]::new('sa', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))

            $null = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -SqlCredential $credential -Folder 'Finance' -Project 'Sales'

            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $SqlCredential.UserName -eq 'sa'
            }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the folder does not exist' {
            Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Nope' -Project 'Sales' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Warns and returns nothing when the project does not exist' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists references of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisEnvironmentReference
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }
    }
}
