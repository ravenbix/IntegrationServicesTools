function Set-SsisFolderObject
{
    <#
        .SYNOPSIS
            Updates a catalog folder's description and persists the change.

        .DESCRIPTION
            Sets the Description property on the supplied CatalogFolder object then calls Alter() to
            persist the change to the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Set-SsisFolderObject -Folder $folder -Description 'Updated description'

            Updates the folder description and persists it.

        .PARAMETER Folder
            The CatalogFolder object to modify, as returned by Get-SsisFolderObject.

        .PARAMETER Description
            The new description to store on the folder. Pass an empty string to clear it.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisFolder) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process
    {
        $Folder.Description = $Description
        $Folder.Alter()
        return $Folder
    }
}
