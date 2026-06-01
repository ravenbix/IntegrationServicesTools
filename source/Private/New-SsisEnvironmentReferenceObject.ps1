function New-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Adds an environment reference to an SSISDB project and persists it.

        .DESCRIPTION
            Adds a reference binding the project to an environment and calls Alter() on the project to
            persist it. When EnvironmentFolder is supplied an absolute reference (to that folder's
            environment) is created; otherwise a relative reference (to an environment in the project's
            own folder) is created. Internal interop helper, not exported from the module.

        .EXAMPLE
            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod'

            Adds a relative reference from the project to the Prod environment in its own folder.

        .PARAMETER Project
            The SSISDB ProjectInfo object to add the environment reference to.

        .PARAMETER Environment
            The name of the environment to reference from the project.

        .PARAMETER EnvironmentFolder
            The folder of the environment for an absolute reference. Omit for a relative reference to an
            environment in the project's own folder.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisEnvironmentReference) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter(Mandatory = $true)]
        [string]
        $Environment,

        [Parameter()]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('EnvironmentFolder'))
        {
            $null = $Project.References.Add($Environment, $EnvironmentFolder)
        }
        else
        {
            $null = $Project.References.Add($Environment)
        }

        $Project.Alter()
    }
}
