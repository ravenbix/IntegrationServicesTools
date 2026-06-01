function Remove-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Removes an environment reference from an SSISDB project and persists the change.

        .DESCRIPTION
            Removes the supplied environment reference from the project's References collection and calls
            Alter() on the project to persist the removal. Internal interop helper, not exported from the
            module.

        .EXAMPLE
            Remove-SsisEnvironmentReferenceObject -Project $project -Reference $reference

            Removes the supplied reference from the project and alters it to persist the change.

        .PARAMETER Project
            The SSISDB ProjectInfo object the reference belongs to and is altered to persist the change.

        .PARAMETER Reference
            The EnvironmentReference object to remove, as returned by Get-SsisEnvironmentReferenceObject.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironmentReference) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter(Mandatory = $true)]
        [object]
        $Reference
    )

    process
    {
        $null = $Project.References.Remove($Reference)
        $Project.Alter()
    }
}
