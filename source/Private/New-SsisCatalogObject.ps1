function New-SsisCatalogObject
{
    <#
        .SYNOPSIS
            Creates the SSISDB catalog on a server and returns the new Catalog object.

        .DESCRIPTION
            Constructs a Microsoft.SqlServer.Management.IntegrationServices.Catalog with the supplied
            encryption password and calls Create() to provision SSISDB on the server represented by
            the IntegrationServices object. Internal interop helper, not exported from the module.

        .EXAMPLE
            $catalog = New-SsisCatalogObject -IntegrationServices $is -Password $securePassword

            Creates the SSISDB catalog and returns it.

        .PARAMETER IntegrationServices
            The IntegrationServices object (from Connect-SsisCatalog) representing the target server.

        .PARAMETER Password
            The catalog encryption password as plain text, used to protect sensitive catalog data.

        .PARAMETER Name
            The catalog name to create. The SSIS catalog must be named 'SSISDB', so this defaults to
            that value and rarely needs to be changed.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Catalog')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $IntegrationServices,

        [Parameter(Mandatory = $true)]
        [string]
        $Password,

        [Parameter()]
        [string]
        $Name = 'SSISDB'
    )

    process
    {
        $catalog = [Microsoft.SqlServer.Management.IntegrationServices.Catalog]::new($IntegrationServices, $Name, $Password)
        $catalog.Create()
        return $catalog
    }
}
