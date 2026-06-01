function Remove-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Drops an environment from an SSISDB catalog.

        .DESCRIPTION
            Calls Drop() on the supplied EnvironmentInfo object to remove it (and its variables) from the
            catalog on the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisEnvironmentObject -Environment $environment

            Drops the environment from the catalog.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object to drop, as returned by Get-SsisEnvironmentObject.

        .OUTPUTS
            None
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironment) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment
    )

    process
    {
        $Environment.Drop()
    }
}
