function Remove-SsisEnvironment
{
    <#
        .SYNOPSIS
            Removes an environment from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and drops an environment (and its variables)
            from a folder in the SSISDB catalog. Accepts a piped Ssis.Environment object. Writes an error
            when the catalog, folder, or named environment does not exist. This is a destructive
            operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod'

            Removes the Prod environment from the Finance folder on the named instance, prompting
            for confirmation first (ConfirmImpact is High).

        .EXAMPLE
            Remove-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' -Confirm:$false

            Removes the Prod environment without prompting for confirmation.

        .EXAMPLE
            Remove-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' -WhatIf

            Reports that the Prod environment would be removed without making any change, then
            returns.

        .EXAMPLE
            $cred = Get-Credential
            Remove-SsisEnvironment -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Folder 'Finance' -Name 'Prod' -Confirm:$false

            Connects with SQL Server authentication using the supplied credential and removes the
            Prod environment from the Finance folder.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Remove-SsisEnvironment

            Removes the piped Prod environment (the ByObject parameter set, reusing the
            environment's existing connection).

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment to remove.

        .PARAMETER InputObject
            A piped Ssis.Environment object to remove, instead of -SqlInstance/-Folder/-Name, keeping
            the existing connection from a Get-SsisEnvironment pipeline.

        .PARAMETER Name
            The name of the environment to remove from the folder.

        .OUTPUTS
            None
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByInstance')]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environment = $InputObject
            $environmentName = $environment.Name
        }
        else
        {
            $connectParameters = @{ SqlInstance = $SqlInstance }

            if ($PSBoundParameters.ContainsKey('SqlCredential'))
            {
                $connectParameters['SqlCredential'] = $SqlCredential
            }

            $integrationServices = Connect-SsisCatalog @connectParameters

            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            if ($null -eq $catalog)
            {
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $environment = Get-SsisEnvironmentObject -Folder $folderObject -Name $Name

            if ($null -eq $environment)
            {
                Write-Error -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Name, $Folder)
                return
            }

            $environmentName = $Name
        }

        if ($PSCmdlet.ShouldProcess($environmentName, 'Remove SSIS environment'))
        {
            Remove-SsisEnvironmentObject -Environment $environment
        }
    }
}
