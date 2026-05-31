function Set-SsisCatalog
{
    <#
        .SYNOPSIS
            Configures properties of the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and updates the SSISDB catalog
            configuration. Only the parameters you supply are changed; the rest are left as-is. Writes
            an error when the catalog does not exist. Returns the updated catalog as an Ssis.Catalog
            object.

        .EXAMPLE
            Set-SsisCatalog -SqlInstance 'SQL01\PROD' -MaxProjectVersions 5 -RetentionDays 365

            Sets the maximum project versions and the operation-log retention window.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER EncryptionAlgorithm
            The catalog encryption algorithm to set. One of TRIPLE_DES_3KEY, AES_128, AES_192 or
            AES_256. Changing this re-encrypts catalog data and can be slow.

        .PARAMETER MaxProjectVersions
            The maximum number of versions retained per project before the version-cleanup job
            removes the oldest versions.

        .PARAMETER RetentionDays
            The number of days operation history is retained (maps to the catalog
            OperationLogRetentionTime property) before the cleanup job removes it.

        .PARAMETER OperationCleanupEnabled
            Whether the periodic operation-cleanup job is enabled, controlling automatic removal of
            old operation history.

        .PARAMETER VersionCleanupEnabled
            Whether the periodic project-version-cleanup job is enabled, controlling automatic removal
            of old project versions.
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

        [Parameter()]
        [ValidateSet('TRIPLE_DES_3KEY', 'AES_128', 'AES_192', 'AES_256')]
        [string]
        $EncryptionAlgorithm,

        [Parameter()]
        [int]
        $MaxProjectVersions,

        [Parameter()]
        [int]
        $RetentionDays,

        [Parameter()]
        [bool]
        $OperationCleanupEnabled,

        [Parameter()]
        [bool]
        $VersionCleanupEnabled
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

        # Map friendly parameter names to MOM Catalog property names.
        $propertyMap = @{
            EncryptionAlgorithm     = 'EncryptionAlgorithm'
            MaxProjectVersions      = 'MaxProjectVersions'
            RetentionDays           = 'OperationLogRetentionTime'
            OperationCleanupEnabled = 'OperationCleanupEnabled'
            VersionCleanupEnabled   = 'VersionCleanupEnabled'
        }

        $changes = @{}

        foreach ($parameterName in $propertyMap.Keys)
        {
            if ($PSBoundParameters.ContainsKey($parameterName))
            {
                $changes[$propertyMap[$parameterName]] = $PSBoundParameters[$parameterName]
            }
        }

        if ($changes.Count -eq 0)
        {
            Write-Warning -Message 'No catalog properties were specified; nothing to change.'
            return
        }

        if ($PSCmdlet.ShouldProcess([string] $SqlInstance, 'Update SSISDB catalog configuration'))
        {
            $updated = Set-SsisCatalogObject -Catalog $catalog -Property $changes
            $updated | Add-SsisTypeName -TypeName 'Ssis.Catalog'
        }
    }
}
