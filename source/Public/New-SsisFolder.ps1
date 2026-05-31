function New-SsisFolder
{
    <#
        .SYNOPSIS
            Creates a folder in the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and creates a folder in the SSISDB catalog.
            Writes an error and makes no change when a folder with the same name already exists, or
            when the catalog does not exist. Returns the new folder as an Ssis.Folder object.

        .EXAMPLE
            New-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' -Description 'Finance projects'

            Creates the Finance folder in the SSISDB catalog on the named instance.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Name
            The name of the folder to create within the SSISDB catalog.

        .PARAMETER Description
            An optional description stored on the folder. Defaults to an empty string when omitted.
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

        [Parameter()]
        [string]
        $Description = ''
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
            Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''. Create it with New-SsisCatalog.' -f $SqlInstance)
            return
        }

        if ($null -ne (Get-SsisFolderObject -Catalog $catalog -Name $Name))
        {
            Write-Error -Message ('A folder named ''{0}'' already exists in the SSISDB catalog.' -f $Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create SSIS catalog folder'))
        {
            $folder = New-SsisFolderObject -Catalog $catalog -Name $Name -Description $Description
            $folder | Add-SsisTypeName -TypeName 'Ssis.Folder'
        }
    }
}
