function New-SsisCatalog
{
    <#
        .SYNOPSIS
            Creates the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and creates the SSISDB Integration Services
            catalog, protected by the supplied encryption password. Writes an error and makes no
            change when the catalog already exists. Returns the new catalog as an Ssis.Catalog object.

        .EXAMPLE
            New-SsisCatalog -SqlInstance 'SQL01\PROD' -CatalogPassword (Get-Credential)

            Creates SSISDB on the instance, prompting for the encryption password (only the password
            field is used).

        .PARAMETER SqlInstance
            The SQL Server instance on which to create SSISDB (for example 'SQL01\PROD'), or an SMO
            Server or IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER CatalogPassword
            A PSCredential whose password is used as the SSISDB encryption-key password. The user name
            portion is ignored; only the password protects the catalog's sensitive data.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType('Ssis.Catalog')]
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
        [System.Management.Automation.PSCredential]
        $CatalogPassword
    )

    process
    {
        $connectParameters = @{ SqlInstance = $SqlInstance }

        if ($PSBoundParameters.ContainsKey('SqlCredential'))
        {
            $connectParameters['SqlCredential'] = $SqlCredential
        }

        $integrationServices = Connect-SsisCatalog @connectParameters

        if ($null -ne (Get-SsisCatalogObject -IntegrationServices $integrationServices))
        {
            Write-Error -Message ('The SSISDB catalog already exists on ''{0}''.' -f $SqlInstance)
            return
        }

        if ($PSCmdlet.ShouldProcess([string] $SqlInstance, 'Create SSISDB catalog'))
        {
            $catalog = New-SsisCatalogObject -IntegrationServices $integrationServices -Password $CatalogPassword.Password
            $catalog | Add-SsisTypeName -TypeName 'Ssis.Catalog'
        }
    }
}
