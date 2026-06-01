function Get-SsisOperation
{
    <#
        .SYNOPSIS
            Gets operations (executions, deployments, validations) from the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB operations as
            Ssis.Operation objects. Returns a single operation when -OperationId is given; otherwise
            lists operations, narrowed by -Status and/or capped to the most recent N by -Top. Accepts
            a piped Ssis.Catalog to list its operations without reconnecting. Writes a warning and
            returns nothing when the catalog does not exist.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 7

            Returns the operation with id 7.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -Top 20

            Returns the 20 most recent operations, newest first.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -Status 'Failed'

            Returns every failed operation in the catalog.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER OperationId
            The numeric id of a single operation to return. When given, the -Status and -Top
            parameters are ignored.

        .PARAMETER InputObject
            A piped Ssis.Catalog object whose operations to list, used instead of -SqlInstance to
            keep the existing connection.

        .PARAMETER Status
            Returns only operations in the given status (for example Running, Success, Failed).

        .PARAMETER Top
            Caps the output to the most recent N operations (highest id first). Applies when listing;
            ignored when -OperationId is given.

        .OUTPUTS
            Ssis.Operation
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Operation')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(ParameterSetName = 'ByInstance')]
        [long]
        $OperationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateSet('Created', 'Running', 'Canceled', 'Failed', 'Pending', 'UnexpectTerminated', 'Success', 'Stopping', 'Completion')]
        [string]
        $Status,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $Top
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $catalog = $InputObject
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
                Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            if ($PSBoundParameters.ContainsKey('OperationId'))
            {
                $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $OperationId

                if ($null -eq $operation)
                {
                    Write-Warning -Message ('Operation ''{0}'' was not found in the SSISDB catalog.' -f $OperationId)
                    return
                }

                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }
        }

        $operations = Get-SsisOperationObject -Catalog $catalog

        if ($PSBoundParameters.ContainsKey('Top'))
        {
            $hasStatus = $PSBoundParameters.ContainsKey('Status')

            $operations |
                Where-Object -FilterScript { $null -ne $_ -and (-not $hasStatus -or $_.Status.ToString() -eq $Status) } |
                Sort-Object -Property Id -Descending |
                Select-Object -First $Top |
                ForEach-Object -Process { $_ | Add-SsisTypeName -TypeName 'Ssis.Operation' }

            return
        }

        foreach ($operation in $operations)
        {
            if ($null -eq $operation)
            {
                continue
            }

            if ($PSBoundParameters.ContainsKey('Status') -and $operation.Status.ToString() -ne $Status)
            {
                continue
            }

            $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
        }
    }
}
