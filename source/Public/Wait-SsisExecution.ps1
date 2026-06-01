function Wait-SsisExecution
{
    <#
        .SYNOPSIS
            Waits for an SSISDB execution to reach a terminal state.

        .DESCRIPTION
            Polls an execution, refreshing it every -PollInterval seconds, until its status becomes
            terminal (Succeeded, Failed, Cancelled, EndedUnexpectedly or Completed), then returns the
            completed Ssis.Execution. When -Timeout is greater than zero and the wait exceeds it, a
            non-terminating error is written and the still-running execution is returned, so callers
            can escalate with -ErrorAction Stop or inspect the returned Status. Accepts an execution by
            id (connecting to the instance) or a piped Ssis.Execution.

        .EXAMPLE
            Wait-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Waits for execution 42 to finish and returns the completed execution.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' | Wait-SsisExecution -Timeout 600

            Starts a package and waits up to ten minutes for it to finish.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution to wait for.

        .PARAMETER InputObject
            A piped Ssis.Execution object to wait for, used instead of -SqlInstance/-ExecutionId to
            keep the existing connection.

        .PARAMETER PollInterval
            Seconds to wait between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            Maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
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
        $terminalStates = @('Succeeded', 'Failed', 'Cancelled', 'EndedUnexpectedly', 'Completed')

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

        $elapsed = 0

        while ($true)
        {
            $execution = Update-SsisExecutionObject -Execution $execution

            if ($terminalStates -contains $execution.Status.ToString())
            {
                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            if ($Timeout -gt 0 -and $elapsed -ge $Timeout)
            {
                Write-Error -Message ('Timed out after about {0} seconds (limit {1}) waiting for execution ''{2}''; current status is ''{3}''.' -f $elapsed, $Timeout, $execution.Id, $execution.Status)
                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            Start-Sleep -Seconds $PollInterval
            $elapsed += $PollInterval
        }
    }
}
