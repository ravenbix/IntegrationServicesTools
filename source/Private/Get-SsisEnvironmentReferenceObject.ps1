function Get-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Returns the environment references defined on an SSISDB project.

        .DESCRIPTION
            Returns the project's References collection, where each item binds the project to an
            environment (relative when no folder is set, absolute otherwise). Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $references = Get-SsisEnvironmentReferenceObject -Project $project

            Returns every environment reference defined on the project.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose environment references to read, as returned by
            Get-SsisProjectObject.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentReference')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        return $Project.References
    }
}
