BeforeDiscovery {
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:folderName = 'ISTools_IntegrationTest'

    # Start from a known-clean state in case a previous run was interrupted.
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }
}

AfterAll {
    # Remove the test folder if any assertion left it behind.
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'SSIS folder lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Creates a folder and returns it tagged Ssis.Folder' {
        $folder = New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Created by integration test' -Confirm:$false

        $folder.PSObject.TypeNames | Should -Contain 'Ssis.Folder'
        $folder.Name | Should -Be $script:folderName
    }

    It 'Gets the created folder by name' {
        $folder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName

        $folder.Name | Should -Be $script:folderName
        $folder.Description | Should -Be 'Created by integration test'
    }

    It 'Updates the folder description' {
        Set-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Updated by integration test' -Confirm:$false | Out-Null

        (Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName).Description | Should -Be 'Updated by integration test'
    }

    It 'Lists the folder among all folders' {
        $names = (Get-SsisFolder -SqlInstance $script:instance).Name

        $names | Should -Contain $script:folderName
    }

    It 'Removes the folder' {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false

        Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
