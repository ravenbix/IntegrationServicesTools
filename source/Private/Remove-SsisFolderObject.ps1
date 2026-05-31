function Remove-SsisFolderObject
{
    <#
        .SYNOPSIS
            Drops a folder from an SSISDB Catalog.

        .DESCRIPTION
            Calls Drop() on the supplied CatalogFolder object to remove it (and its contents) from the
            catalog on the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisFolderObject -Folder $folder

            Drops the folder from the catalog.

        .PARAMETER Folder
            The CatalogFolder object to drop, as returned by Get-SsisFolderObject.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder
    )

    process
    {
        $Folder.Drop()
    }
}
