function Remove-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Removes a variable from an SSISDB environment and persists the change.

        .DESCRIPTION
            Removes the named variable from the environment's Variables collection and calls Alter() on
            the environment to persist the removal. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisEnvironmentVariableObject -Environment $environment -Name 'Port'

            Removes the Port variable from the environment and alters it to persist the change.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variable to remove.

        .PARAMETER Name
            The name of the variable to remove from the environment.

        .OUTPUTS
            None
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironmentVariable) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    process
    {
        $Environment.Variables.Remove($Name)
        $Environment.Alter()
    }
}
