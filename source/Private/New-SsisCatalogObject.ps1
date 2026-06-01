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

        .EXAMPLE
            $securePassword = Read-Host -AsSecureString -Prompt 'Encryption password'
            $catalog = New-SsisCatalogObject -IntegrationServices $is -Password $securePassword -Name 'SSISDB'

            Passes the catalog name explicitly. 'SSISDB' is the default and the only name the SSIS
            catalog supports, so -Name is rarely needed.

        .PARAMETER IntegrationServices
            The IntegrationServices object (from Connect-SsisCatalog) representing the target server.

        .PARAMETER Password
            The catalog encryption password as a SecureString, used to protect sensitive catalog
            data. It is converted to the plain string the object model requires only at the point of
            the call.

        .PARAMETER Name
            The catalog name to create. The SSIS catalog must be named 'SSISDB', so this defaults to
            that value and rarely needs to be changed.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisCatalog) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Catalog')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $IntegrationServices,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $Password,

        [Parameter()]
        [string]
        $Name = 'SSISDB'
    )

    process
    {
        # The MOM Catalog constructor requires the password as a plain string; convert from the
        # SecureString at the last moment via NetworkCredential.
        $plainPassword = [System.Net.NetworkCredential]::new('', $Password).Password
        $catalog = [Microsoft.SqlServer.Management.IntegrationServices.Catalog]::new($IntegrationServices, $Name, $plainPassword)
        $catalog.Create()
        return $catalog
    }
}
