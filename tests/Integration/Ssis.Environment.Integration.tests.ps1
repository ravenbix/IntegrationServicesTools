BeforeDiscovery {
    $script:skip = [string]::IsNullOrWhiteSpace($env:SSIS_TEST_INSTANCE)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:skip = [string]::IsNullOrWhiteSpace($script:instance)

    $script:folderName = 'ISTools_EnvTest'
    $script:environmentName = 'IntegrationEnv'
}

AfterAll {
    if (-not $script:skip)
    {
        # Best-effort cleanup; ignore errors if a prior step failed before creating an object.
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Environment lifecycle' -Tag 'Integration' {
    It 'Creates, populates, reads, updates, and removes an environment end to end' -Skip:$script:skip {
        # Arrange: a clean folder to hold the environment.
        if ($null -ne (Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName))
        {
            Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
        }
        New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false | Out-Null

        # Create the environment.
        $environment = New-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Description 'integration' -Confirm:$false
        $environment.PSObject.TypeNames | Should -Contain 'Ssis.Environment'

        # Add a typed variable (Int32 inferred) and a sensitive variable.
        $port = Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1433 -Confirm:$false
        $port.Type | Should -Be ([System.TypeCode]::Int32)
        $port.Value | Should -Be 1433

        Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Password' -Value 'p@ss' -Sensitive -Confirm:$false | Out-Null

        # Read them back.
        $variables = Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName
        ($variables | Measure-Object).Count | Should -Be 2
        ($variables | Where-Object -FilterScript { $_.Name -eq 'Password' }).Sensitive | Should -BeTrue

        # Update the Port value (upsert path).
        $updated = Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1450 -Confirm:$false
        $updated.Value | Should -Be 1450

        # Retype the variable in place (Int32 -> String) by setting a string value.
        $retyped = Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 'localhost' -Confirm:$false
        $retyped.Type | Should -Be ([System.TypeCode]::String)
        $retyped.Value | Should -Be 'localhost'

        # Remove a variable.
        Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' |
            Remove-SsisEnvironmentVariable -Confirm:$false
        $remaining = Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName
        ($remaining | Measure-Object).Count | Should -Be 1

        # Remove the environment.
        Remove-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Confirm:$false
        Get-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
    }
}
