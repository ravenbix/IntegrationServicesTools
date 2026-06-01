function Publish-SsisProjectObject
{
    <#
        .SYNOPSIS
            Deploys an .ispac project into an SSISDB catalog folder.

        .DESCRIPTION
            Calls DeployProject(name, bytes) on the supplied CatalogFolder object to deploy a project
            from its .ispac byte content. The deploy is synchronous. Internal interop helper, not
            exported from the module.

        .EXAMPLE
            Publish-SsisProjectObject -Folder $folder -Name 'Sales' -ProjectBytes $bytes

            Deploys the Sales project into the folder from the supplied .ispac bytes.

        .PARAMETER Folder
            The target SSISDB CatalogFolder object the project is deployed into.

        .PARAMETER Name
            The catalog project name to create or update with this deployment.

        .PARAMETER ProjectBytes
            The raw bytes of the .ispac project file to deploy into the catalog.

        .OUTPUTS
            None. The method call on the folder object has no return value.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [byte[]]
        $ProjectBytes
    )

    process
    {
        $Folder.DeployProject($Name, $ProjectBytes)
    }
}
