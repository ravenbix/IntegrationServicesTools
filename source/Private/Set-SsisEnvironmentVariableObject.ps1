function Set-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Adds or updates a variable on an SSISDB environment and persists the change.

        .DESCRIPTION
            When the named variable already exists on the environment its type, value, sensitivity, and
            description are updated; otherwise a new variable is added. In both cases the variable takes
            the supplied type code. The change is persisted by calling Alter() on the environment.
            Internal interop helper, not exported from the module.

        .EXAMPLE
            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $false -Description 'db port'

            Adds or updates the Port variable and alters the environment to persist it.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variable to add or update.

        .PARAMETER Name
            The name of the variable to add or update on the environment.

        .PARAMETER Value
            The value to store in the variable. Its meaning follows the variable's type code.

        .PARAMETER TypeCode
            The System.TypeCode the variable is given, whether it is being created or updated.

        .PARAMETER Sensitive
            Whether the variable value is stored encrypted (sensitive) on the server.

        .PARAMETER Description
            A description stored on the variable. Pass an empty string when no description is wanted.

        .OUTPUTS
            None
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisEnvironmentVariable) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.TypeCode]
        $TypeCode,

        [Parameter(Mandatory = $true)]
        [bool]
        $Sensitive,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process
    {
        if ($Environment.Variables.Contains($Name))
        {
            $variable = $Environment.Variables[$Name]
            $variable.Type = $TypeCode
            $variable.Value = $Value
            $variable.Sensitive = $Sensitive
            $variable.Description = $Description
        }
        else
        {
            $Environment.Variables.Add($Name, $TypeCode, $Value, $Sensitive, $Description)
        }

        $Environment.Alter()
    }
}
