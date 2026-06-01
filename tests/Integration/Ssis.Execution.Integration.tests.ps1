BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_ExecTest'
    $script:projectName = 'ISTools_TestProject'
    # Package name confirmed from New-TestProjectIspac.ps1: PackageItems.Add($package, 'Package.dtsx')
    $script:packageName = 'Package.dtsx'

    $script:removeFolderIfPresent = {
        param ($instance, $folderName)

        if (Get-SsisFolder -SqlInstance $instance -Name $folderName -WarningAction SilentlyContinue)
        {
            Get-SsisProject -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisProject -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

            Get-SsisEnvironment -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisEnvironment -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

            Remove-SsisFolder -SqlInstance $instance -Name $folderName -Confirm:$false
        }
    }

    & $script:removeFolderIfPresent $script:instance $script:folderName

    New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Created by integration test' -Confirm:$false | Out-Null
    Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false | Out-Null
}

AfterAll {
    & $script:removeFolderIfPresent $script:instance $script:folderName

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Execution lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Starts a package synchronously and reports a terminal status' {
        $splatStart = @{
            SqlInstance  = $script:instance
            Folder       = $script:folderName
            Project      = $script:projectName
            Package      = $script:packageName
            LoggingLevel = 'Basic'
            Synchronous  = $true
            Timeout      = 300
            Confirm      = $false
        }
        $execution = Start-SsisExecution @splatStart
        $execution.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        $execution.Status.ToString() | Should -BeIn @('Succeeded', 'Failed', 'Completed')
    }

    It 'Finds the execution by id and by status' {
        $splatStart = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Package     = $script:packageName
            Synchronous = $true
            Timeout     = 300
            Confirm     = $false
        }
        $started = Start-SsisExecution @splatStart

        $byId = Get-SsisExecution -SqlInstance $script:instance -ExecutionId $started.Id
        $byId.Id | Should -Be $started.Id

        $splatGet = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Package     = $script:packageName
        }
        $byPackage = Get-SsisExecution @splatGet
        ($byPackage | Measure-Object).Count | Should -BeGreaterThan 0
    }
}
