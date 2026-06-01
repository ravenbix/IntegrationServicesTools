function Get-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Returns environment-variable object(s) from an SSISDB environment.

        .DESCRIPTION
            Returns the named variable from the environment's Variables collection, or all variables when
            no name is given. Returns $null when a named variable does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $variable = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'ConnString'

            Returns the ConnString variable, or $null when it does not exist.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variables to read, as returned by Get-SsisEnvironmentObject.

        .PARAMETER Name
            The variable name to return. When omitted, every variable in the environment is returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.EnvironmentVariableInfo
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentVariableInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Environment.Variables.Contains($Name))
            {
                return $Environment.Variables[$Name]
            }

            return $null
        }

        return $Environment.Variables
    }
}
