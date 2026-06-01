function Wait-SsisOperation
{
    <#
        .SYNOPSIS
            Waits for an SSISDB operation to reach a terminal state.

        .DESCRIPTION
            Polls an operation, refreshing it every -PollInterval seconds, until its status becomes
            terminal (Success, Failed, Canceled, UnexpectTerminated or Completion), then returns the
            completed Ssis.Operation. When -Timeout is greater than zero and the wait exceeds it, a
            non-terminating error is written and the still-running operation is returned, so callers
            can escalate with -ErrorAction Stop or inspect the returned Status. Accepts an operation by
            id (connecting to the instance) or a piped Ssis.Operation. It is general: any operation
            (validation, execution or deployment) can be waited on.

        .EXAMPLE
            Wait-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 42

            Waits for operation 42 to finish and returns the completed operation.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Confirm:$false | Wait-SsisOperation -Timeout 120

            Starts a project validation and waits up to two minutes for it to finish.

        .EXAMPLE
            $cred = Get-Credential
            Wait-SsisOperation -SqlInstance 'SQL01\PROD' -SqlCredential $cred -OperationId 42

            Connects with SQL Server authentication using the supplied credential and waits for
            operation 42 to finish.

        .EXAMPLE
            Wait-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 42 -PollInterval 1 -Timeout 30

            Refreshes the operation status every second and waits up to 30 seconds before writing a
            non-terminating error and returning the still-running operation.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 42 | Wait-SsisOperation

            Pipes an operation in (the ByObject parameter set) and waits for it without reconnecting.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER OperationId
            The numeric id of the operation to wait for.

        .PARAMETER InputObject
            A piped Ssis.Operation object to wait for, used instead of -SqlInstance/-OperationId to
            keep the existing connection.

        .PARAMETER PollInterval
            Seconds to wait between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            Maximum seconds to wait. 0 (the default) waits indefinitely.

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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [long]
        $OperationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $Timeout = 0
    )

    process
    {
        $terminalStates = @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $operation = $InputObject
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

            $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $OperationId

            if ($null -eq $operation)
            {
                Write-Warning -Message ('Operation ''{0}'' was not found in the SSISDB catalog.' -f $OperationId)
                return
            }
        }

        $elapsed = 0

        while ($true)
        {
            $operation = Update-SsisOperationObject -Operation $operation

            if ($terminalStates -contains $operation.Status.ToString())
            {
                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }

            if ($Timeout -gt 0 -and $elapsed -ge $Timeout)
            {
                Write-Error -Message ('Timed out after about {0} seconds (limit {1}) waiting for operation ''{2}''; current status is ''{3}''.' -f $elapsed, $Timeout, $operation.Id, $operation.Status)
                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }

            Start-Sleep -Seconds $PollInterval
            $elapsed += $PollInterval
        }
    }
}
