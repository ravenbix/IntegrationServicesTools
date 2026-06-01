function Set-SsisFolder
{
    <#
        .SYNOPSIS
            Updates the description of a folder in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and updates the description of an existing
            SSISDB catalog folder. Writes an error when the catalog or the named folder does not
            exist. Returns the updated folder as an Ssis.Folder object.

        .EXAMPLE
            Set-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -Description 'Updated'

            Updates the Finance folder's description on the named instance.

        .EXAMPLE
            Set-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -Description ''

            Clears the Finance folder's description by passing an empty string.

        .EXAMPLE
            $cred = Get-Credential
            Set-SsisFolder -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Name 'Finance' -Description 'Updated'

            Connects with SQL Server authentication using the supplied credential and updates the
            Finance folder's description.

        .EXAMPLE
            Set-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -Description 'Updated' -WhatIf

            Reports what would happen without updating the folder.

        .EXAMPLE
            'SQL01\PROD', 'SQL02\PROD' | Set-SsisFolder -Name 'Finance' -Description 'Updated'

            Pipes instance names in and updates the Finance folder's description on each instance's
            catalog in turn.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Name
            The name of the existing folder whose description should be updated.

        .PARAMETER Description
            The new description to store on the folder. Pass an empty string to clear it.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType('Ssis.Folder')]
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
        $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
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

        if ($PSCmdlet.ShouldProcess($Name, 'Update SSIS catalog folder'))
        {
            $updated = Set-SsisFolderObject -Folder $folder -Description $Description
            $updated | Add-SsisTypeName -TypeName 'Ssis.Folder'
        }
    }
}
