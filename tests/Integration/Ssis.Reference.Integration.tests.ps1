BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_RefTest'
    $script:projectName = 'ISTools_TestProject'
    $script:environmentName = 'RefEnv'

    # SSISDB only drops EMPTY folders, so a folder must be drained of its projects and environments
    # before it can be removed (used by both setup pre-clean and teardown).
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
}

AfterAll {
    & $script:removeFolderIfPresent $script:instance $script:folderName

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Environment reference and parameter lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Binds a project to an environment and sets a parameter to a referenced variable' {
        # Deploy the project and create an environment with a matching variable in the same folder.
        Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false | Out-Null
        New-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Confirm:$false | Out-Null
        Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1433 -Confirm:$false | Out-Null

        # Create a relative environment reference (environment is in the project's own folder).
        $reference = New-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Environment $script:environmentName -Confirm:$false
        $reference.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'

        # List references.
        $references = Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName
        ($references | Where-Object -FilterScript { $_.Name -eq $script:environmentName } | Measure-Object).Count | Should -Be 1

        # Set the project parameter to a literal, then bind it to the environment variable.
        $literal = Set-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort' -Value 1450 -Confirm:$false
        $literal.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'

        Set-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort' -ReferencedVariable 'Port' -Confirm:$false | Out-Null

        $parameter = Get-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort'
        $parameter.ReferencedVariableName | Should -Be 'Port'

        # Remove the reference via the pipeline.
        Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName |
            Where-Object -FilterScript { $_.Name -eq $script:environmentName } |
            Remove-SsisEnvironmentReference -Confirm:$false
        $after = Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName
        ($after | Where-Object -FilterScript { $_.Name -eq $script:environmentName } | Measure-Object).Count | Should -Be 0
    }
}
