function Get-SsisCatalog
{
    <#
        .SYNOPSIS
            Gets the SSISDB catalog from a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the SSISDB Integration Services
            catalog as an Ssis.Catalog object. Writes a warning and returns nothing when the catalog
            has not been created on the target instance; use New-SsisCatalog to create it.

        .EXAMPLE
            Get-SsisCatalog -SqlInstance 'SQL01\PROD'

            Returns the SSISDB catalog on the named instance using Windows authentication.

        .EXAMPLE
            $cred = Get-Credential
            Get-SsisCatalog -SqlInstance 'SQL01\PROD' -SqlCredential $cred

            Connects with SQL Server authentication using the supplied credential and returns the
            SSISDB catalog.

        .EXAMPLE
            'SQL01\PROD', 'SQL02\PROD' | Get-SsisCatalog

            Pipes instance names in and returns each instance's SSISDB catalog in turn.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).
    #>
    [CmdletBinding()]
    [OutputType('Ssis.Catalog')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $SqlCredential
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
            Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''. Create it with New-SsisCatalog.' -f $SqlInstance)
            return
        }

        $catalog | Add-SsisTypeName -TypeName 'Ssis.Catalog'
    }
}
