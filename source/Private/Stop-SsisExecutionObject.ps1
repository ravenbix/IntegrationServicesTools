function Stop-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Stops a running SSISDB execution.

        .DESCRIPTION
            Calls Stop() on the ExecutionOperation, requesting the server cancel the running package.
            Internal interop helper, not exported from the module.

        .EXAMPLE
            Stop-SsisExecutionObject -Execution $execution

            Requests cancellation of the running execution.

        .PARAMETER Execution
            The ExecutionOperation object to stop, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            None.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Stop-SsisExecution) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        $Execution.Stop()
    }
}
