BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_MonitorTest'
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
    $script:execution = Start-SsisExecution @splatStart
}

AfterAll {
    & $script:removeFolderIfPresent $script:instance $script:folderName

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Execution monitoring (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Returns the execution message log by id' {
        $messages = Get-SsisExecutionMessage -SqlInstance $script:instance -ExecutionId $script:execution.Id
        ($messages | Measure-Object).Count | Should -BeGreaterThan 0
        $messages[0].PSObject.TypeNames | Should -Contain 'Ssis.ExecutionMessage'
    }

    It 'Returns the message log of a piped execution' {
        $messages = $script:execution | Get-SsisExecutionMessage
        ($messages | Measure-Object).Count | Should -BeGreaterThan 0
    }

    It 'Returns the matching operation by id' {
        # An execution is itself an operation sharing the same id.
        $operation = Get-SsisOperation -SqlInstance $script:instance -OperationId $script:execution.Id
        $operation.Id | Should -Be $script:execution.Id
        $operation.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
    }

    It 'Caps a listing to the most recent N with -Top, newest first' {
        $operations = Get-SsisOperation -SqlInstance $script:instance -Top 5
        ($operations | Measure-Object).Count | Should -BeLessOrEqual 5
        if (($operations | Measure-Object).Count -gt 1)
        {
            $operations[0].Id | Should -BeGreaterThan $operations[-1].Id
        }
    }

    It 'Filters operations by -Status' {
        # The completed execution is itself an operation in its terminal status, so filtering by
        # that status must return at least it, and every returned operation must match.
        $status = $script:execution.Status.ToString()
        $filtered = Get-SsisOperation -SqlInstance $script:instance -Status $status
        ($filtered | Measure-Object).Count | Should -BeGreaterThan 0
        ($filtered | Where-Object -FilterScript { $_.Status.ToString() -ne $status } | Measure-Object).Count | Should -Be 0
    }
}
