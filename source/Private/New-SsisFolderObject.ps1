function New-SsisFolderObject
{
    <#
        .SYNOPSIS
            Creates a folder in an SSISDB Catalog and returns the new folder object.

        .DESCRIPTION
            Constructs a Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder under the
            given catalog and calls Create() to persist it. Internal interop helper, not exported
            from the module.

        .EXAMPLE
            $folder = New-SsisFolderObject -Catalog $catalog -Name 'Finance' -Description 'Finance projects'

            Creates the Finance folder and returns it.

        .PARAMETER Catalog
            The SSISDB Catalog object under which to create the folder.

        .PARAMETER Name
            The name of the folder to create within the catalog.

        .PARAMETER Description
            A description stored on the new folder. Pass an empty string when no description is wanted.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisFolder) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

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
        $folder = [Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder]::new($Catalog, $Name, $Description)
        $folder.Create()
        return $folder
    }
}
