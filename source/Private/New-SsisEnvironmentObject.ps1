function New-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Creates an environment in an SSISDB catalog folder and returns the new environment object.

        .DESCRIPTION
            Constructs a Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo under the
            given folder and calls Create() to persist it. Internal interop helper, not exported from
            the module.

        .EXAMPLE
            $environment = New-SsisEnvironmentObject -Folder $folder -Name 'Prod' -Description 'Production'

            Creates the Prod environment in the folder and returns it.

        .PARAMETER Folder
            The SSISDB CatalogFolder object under which to create the environment.

        .PARAMETER Name
            The name of the environment to create within the folder.

        .PARAMETER Description
            A description stored on the new environment. Pass an empty string when no description is wanted.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisEnvironment) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process
    {
        $environment = [Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo]::new($Folder, $Name, $Description)
        $environment.Create()
        return $environment
    }
}
