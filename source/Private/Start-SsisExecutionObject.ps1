function Start-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Starts an SSISDB package execution and returns its id.

        .DESCRIPTION
            Builds the execution value-parameter sets from the logging level (object type 50,
            LOGGING_LEVEL) and each supplied parameter (object type 30 for a package parameter, 20 for
            a project parameter), then calls Execute() on the package with the 32-bit runtime flag and
            the optional environment reference. Returns the numeric execution id. Internal interop
            helper, not exported from the module.

        .EXAMPLE
            $id = Start-SsisExecutionObject -Package $package -Reference $reference -LoggingLevel 'Basic'

            Starts the package with Basic logging bound to the given environment reference.

        .PARAMETER Package
            The SSISDB PackageInfo object to execute, as returned by Get-SsisPackageObject.

        .PARAMETER Reference
            The EnvironmentReference to bind the execution to, or $null for none.

        .PARAMETER Parameter
            A hashtable of parameter name/value overrides to set for this run.

        .PARAMETER LoggingLevel
            One of None, Basic, Performance or Verbose; applied as the LOGGING_LEVEL system value.

        .PARAMETER Use32BitRuntime
            When set, runs the package in the 32-bit runtime.

        .OUTPUTS
            System.Int64
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Start-SsisExecution) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Package,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Reference,

        [Parameter()]
        [hashtable]
        $Parameter,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Performance', 'Verbose')]
        [string]
        $LoggingLevel,

        [Parameter()]
        [switch]
        $Use32BitRuntime
    )

    process
    {
        $loggingValues = @{
            None        = 0
            Basic       = 1
            Performance = 2
            Verbose     = 3
        }

        # PackageInfo.Execute requires a Collection of the concrete MOM ExecutionValueParameterSet
        # type; a generic List or PSCustomObject entries fail .NET's strict argument binding. The MOM
        # assemblies are loaded at module import, so the type is constructible in unit tests too.
        $setValues = [System.Collections.ObjectModel.Collection[Microsoft.SqlServer.Management.IntegrationServices.PackageInfo+ExecutionValueParameterSet]]::new()

        if ($PSBoundParameters.ContainsKey('LoggingLevel'))
        {
            $loggingValueSet = [Microsoft.SqlServer.Management.IntegrationServices.PackageInfo+ExecutionValueParameterSet]::new()
            $loggingValueSet.ObjectType = 50
            $loggingValueSet.ParameterName = 'LOGGING_LEVEL'
            $loggingValueSet.ParameterValue = $loggingValues[$LoggingLevel]
            $setValues.Add($loggingValueSet)
        }

        if ($PSBoundParameters.ContainsKey('Parameter'))
        {
            foreach ($parameterName in $Parameter.Keys)
            {
                if ($Package.Parameters.Contains($parameterName))
                {
                    $objectType = 30
                }
                else
                {
                    $objectType = 20
                }

                $parameterValueSet = [Microsoft.SqlServer.Management.IntegrationServices.PackageInfo+ExecutionValueParameterSet]::new()
                $parameterValueSet.ObjectType = $objectType
                $parameterValueSet.ParameterName = $parameterName
                $parameterValueSet.ParameterValue = $Parameter[$parameterName]
                $setValues.Add($parameterValueSet)
            }
        }

        return $Package.Execute($Use32BitRuntime.IsPresent, $Reference, $setValues)
    }
}
