function Set-SsisParameterObject
{
    <#
        .SYNOPSIS
            Sets the value of an SSISDB parameter and persists the change.

        .DESCRIPTION
            Sets the parameter to a literal value or to a reference to an environment variable, then
            calls Alter() on the owning project to persist the change. The value type is supplied as the
            string 'Literal' or 'Referenced' and mapped to the object model's ParameterValueType here, so
            the rest of the module does not depend on the enum. Internal interop helper, not exported.

        .EXAMPLE
            Set-SsisParameterObject -Parameter $parameter -ValueType 'Literal' -Value 1450 -Project $project

            Sets the parameter to the literal value 1450 and alters the project to persist it.

        .PARAMETER Parameter
            The SSISDB ParameterInfo object whose value to set, as returned by Get-SsisParameterObject.

        .PARAMETER ValueType
            Either 'Literal' (use Value as the parameter value) or 'Referenced' (use Value as the name of
            an environment variable to bind the parameter to).

        .PARAMETER Value
            The literal value, or the environment variable name when ValueType is 'Referenced'.

        .PARAMETER Project
            The owning SSISDB ProjectInfo object, altered to persist the parameter change.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisParameter) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Parameter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Literal', 'Referenced')]
        [string]
        $ValueType,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Value,

        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        $parameterValueType = [Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo+ParameterValueType]::$ValueType
        $Parameter.Set($parameterValueType, $Value)
        $Project.Alter()
    }
}
