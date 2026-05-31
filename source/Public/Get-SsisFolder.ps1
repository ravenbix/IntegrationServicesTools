function Get-SsisFolder
{
    <#
        .SYNOPSIS
            Gets folders from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB catalog folders as
            Ssis.Folder objects. Returns all folders by default, or a single folder when -Name is
            given. Writes a warning and returns nothing when the catalog does not exist or the named
            folder is not found.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD'

            Returns every folder in the SSISDB catalog on the named instance.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Name
            The name of a specific folder to return. When omitted, all folders in the catalog are
            returned.
    #>
    [CmdletBinding()]
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

        [Parameter()]
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
            Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
            return
        }

        $folderParameters = @{ Catalog = $catalog }

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $folderParameters['Name'] = $Name
        }

        $folders = Get-SsisFolderObject @folderParameters

        if ($null -eq $folders)
        {
            Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Name)
            return
        }

        $folders | Add-SsisTypeName -TypeName 'Ssis.Folder'
    }
}
