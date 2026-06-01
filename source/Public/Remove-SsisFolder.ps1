function Remove-SsisFolder
{
    <#
        .SYNOPSIS
            Removes a folder from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and drops a folder (and its contents) from
            the SSISDB catalog. Writes an error when the catalog or the named folder does not exist.
            This is a destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance'

            Removes the Finance folder from the SSISDB catalog on the named instance, prompting for
            confirmation first.

        .EXAMPLE
            Remove-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -Confirm:$false

            Removes the Finance folder without prompting for confirmation.

        .EXAMPLE
            $cred = Get-Credential
            Remove-SsisFolder -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Name 'Finance' -Confirm:$false

            Connects with SQL Server authentication using the supplied credential and removes the
            Finance folder without prompting.

        .EXAMPLE
            Remove-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -WhatIf

            Reports what would happen without removing the folder.

        .EXAMPLE
            'SQL01\PROD', 'SQL02\PROD' | Remove-SsisFolder -Name 'Finance' -Confirm:$false

            Pipes instance names in and removes the Finance folder from each instance's catalog in turn.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Name
            The name of the folder to remove from the SSISDB catalog.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    process
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

        $folder = Get-SsisFolderObject -Catalog $catalog -Name $Name

        if ($null -eq $folder)
        {
            Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove SSIS catalog folder'))
        {
            Remove-SsisFolderObject -Folder $folder
        }
    }
}
