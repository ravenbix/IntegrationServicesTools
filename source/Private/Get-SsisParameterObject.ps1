function Get-SsisParameterObject
{
    <#
        .SYNOPSIS
            Returns parameter object(s) from an SSISDB project or package.

        .DESCRIPTION
            Returns the named parameter from the container's Parameters collection, or all parameters
            when no name is given. Returns $null when a named parameter does not exist. The container is
            an SSISDB ProjectInfo (project-level parameters) or PackageInfo (package-level parameters).
            Internal interop helper, not exported from the module.

        .EXAMPLE
            $parameter = Get-SsisParameterObject -Container $project -Name 'TargetPort'

            Returns the TargetPort project parameter, or $null when it does not exist.

        .PARAMETER Container
            The SSISDB ProjectInfo or PackageInfo whose parameters to read. Both expose a Parameters
            collection.

        .PARAMETER Name
            The parameter name to return. When omitted, every parameter on the container is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Container,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Container.Parameters.Contains($Name))
            {
                return $Container.Parameters[$Name]
            }

            return $null
        }

        return $Container.Parameters
    }
}
