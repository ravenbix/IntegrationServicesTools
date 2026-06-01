function Stop-SsisExecution
{
    <#
        .SYNOPSIS
            Stops a running SSISDB execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Execution) and requests
            cancellation of the execution. Silent by default; with -PassThru it refreshes and returns
            the Ssis.Execution (now Stopping or Canceled). Writes an error and makes no change when
            the catalog or execution does not exist. Because cancelling an in-flight run is
            irreversible, the command prompts by default (ConfirmImpact High); suppress with
            -Confirm:$false.

        .EXAMPLE
            Stop-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42 -Confirm:$false

            Cancels execution 42 without prompting.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Running' | Stop-SsisExecution -PassThru -Confirm:$false | Wait-SsisExecution

            Cancels every running execution and waits for each to settle.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution to stop.

        .PARAMETER InputObject
            A piped Ssis.Execution object to stop, used instead of -SqlInstance/-ExecutionId to keep
            the existing connection.

        .PARAMETER PassThru
            Returns the refreshed Ssis.Execution after stopping. By default the command emits nothing.

        .OUTPUTS
            None, or Ssis.Execution when -PassThru is specified.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByInstance')]
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
        [switch]
        $PassThru
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $execution = $InputObject
            $executionId = $InputObject.Id
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
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

            if ($null -eq $execution)
            {
                Write-Error -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                return
            }

            $executionId = $ExecutionId
        }

        if ($PSCmdlet.ShouldProcess($executionId, 'Stop SSIS execution'))
        {
            Stop-SsisExecutionObject -Execution $execution

            if ($PassThru)
            {
                $refreshed = Update-SsisExecutionObject -Execution $execution
                $refreshed | Add-SsisTypeName -TypeName 'Ssis.Execution'
            }
        }
    }
}
