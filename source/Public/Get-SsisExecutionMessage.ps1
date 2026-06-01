function Get-SsisExecutionMessage
{
    <#
        .SYNOPSIS
            Gets the message log of an SSISDB execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the messages recorded for a
            single execution as Ssis.ExecutionMessage objects, or reads the messages of a piped
            Ssis.Execution without reconnecting. Every message is returned; narrow the results with
            Where-Object (for example on MessageType). Writes a warning and returns nothing when the
            catalog or the execution does not exist.

        .EXAMPLE
            Get-SsisExecutionMessage -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Returns every message logged for execution 42.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Failed' | Get-SsisExecutionMessage

            Returns the messages of each failed execution.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution whose messages to return.

        .PARAMETER InputObject
            A piped Ssis.Execution object whose messages to read, used instead of
            -SqlInstance/-ExecutionId to keep the existing connection.

        .OUTPUTS
            Ssis.ExecutionMessage
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.ExecutionMessage')]
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
        [long]
        $ExecutionId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $execution = $InputObject
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

            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

            if ($null -eq $execution)
            {
                Write-Warning -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                return
            }
        }

        $messages = Get-SsisExecutionMessageObject -Execution $execution

        foreach ($message in $messages)
        {
            if ($null -eq $message)
            {
                continue
            }

            $message | Add-SsisTypeName -TypeName 'Ssis.ExecutionMessage'
        }
    }
}
