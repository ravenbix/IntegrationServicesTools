BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_ValidationTest'
    $script:projectName = 'ISTools_TestProject'
    # Package name confirmed from New-TestProjectIspac.ps1: PackageItems.Add($package, 'Package.dtsx')
    $script:packageName = 'Package.dtsx'

    $script:removeFolderIfPresent = {
        param ($instance, $folderName)

        if (Get-SsisFolder -SqlInstance $instance -Name $folderName -WarningAction SilentlyContinue)
        {
            Get-SsisProject -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisProject -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

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

Describe 'Validation (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Validates a project synchronously and reports a terminal status' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Synchronous = $true
            Timeout     = 120
            Confirm     = $false
        }
        $operation = Start-SsisValidation @splatValidate
        $operation.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        $operation.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }

    It 'Validates a single package synchronously' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Package     = $script:packageName
            Synchronous = $true
            Timeout     = 120
            Confirm     = $false
        }
        $operation = Start-SsisValidation @splatValidate
        $operation.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }

    It 'Waits on a started validation operation via Wait-SsisOperation' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Confirm     = $false
        }
        $started = Start-SsisValidation @splatValidate
        $completed = $started | Wait-SsisOperation -Timeout 120
        $completed.Id | Should -Be $started.Id
        $completed.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }
}
