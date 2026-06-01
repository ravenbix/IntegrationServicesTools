BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_IntegrationTest'
    $script:projectName = 'ISTools_TestProject'
    $script:exportDir = Join-Path -Path $TestDrive -ChildPath 'export'
    New-Item -ItemType Directory -Path $script:exportDir -Force | Out-Null

    # Start from a known-clean state in case a previous run was interrupted.
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }

    New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Created by integration test' -Confirm:$false | Out-Null
}

AfterAll {
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'SSIS project lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Publishes the .ispac and returns it tagged Ssis.Project' {
        $project = Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false

        $project.PSObject.TypeNames | Should -Contain 'Ssis.Project'
        $project.Name | Should -Be $script:projectName
    }

    It 'Gets the deployed project by folder and name' {
        $project = Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName

        $project.Name | Should -Be $script:projectName
    }

    It 'Lists the project by piping the folder in' {
        $names = (Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName | Get-SsisProject).Name

        $names | Should -Contain $script:projectName
    }

    It 'Gets at least one package tagged Ssis.Package' {
        $packages = Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName | Get-SsisPackage

        ($packages | Measure-Object).Count | Should -BeGreaterThan 0
        $packages[0].PSObject.TypeNames | Should -Contain 'Ssis.Package'
    }

    It 'Exports the project to an .ispac file' {
        $file = Export-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName -Path $script:exportDir -Force -Confirm:$false

        $file.FullName | Should -Exist
        $file.Name | Should -Be ($script:projectName + '.ispac')
    }

    It 'Removes the project' {
        Remove-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName -Confirm:$false

        Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName | Should -BeNullOrEmpty
    }
}
