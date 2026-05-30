BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Add-SsisTypeName' {
    It 'Inserts the type name at the front of the object type list' {
        InModuleScope $script:moduleName {
            $obj = [PSCustomObject]@{ Name = 'x' }
            $result = $obj | Add-SsisTypeName -TypeName 'Ssis.Catalog'
            $result.PSObject.TypeNames[0] | Should -Be 'Ssis.Catalog'
        }
    }

    It 'Passes the same object through unchanged' {
        InModuleScope $script:moduleName {
            $obj = [PSCustomObject]@{ Name = 'x' }
            $result = $obj | Add-SsisTypeName -TypeName 'Ssis.Folder'
            $result.Name | Should -Be 'x'
        }
    }

    It 'Ignores a null input object' {
        InModuleScope $script:moduleName {
            { $null | Add-SsisTypeName -TypeName 'Ssis.Folder' } | Should -Not -Throw
        }
    }
}
