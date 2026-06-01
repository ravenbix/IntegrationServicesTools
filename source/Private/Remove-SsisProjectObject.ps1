function Remove-SsisProjectObject
{
    <#
        .SYNOPSIS
            Drops a project from an SSISDB catalog.

        .DESCRIPTION
            Calls Drop() on the supplied ProjectInfo object to remove it (and its packages) from the
            catalog on the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisProjectObject -Project $project

            Drops the project from the catalog.

        .PARAMETER Project
            The SSISDB ProjectInfo object to drop, as returned by Get-SsisProjectObject.

        .OUTPUTS
            None. The method call on the project object has no return value.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisProject) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        $Project.Drop()
    }
}
