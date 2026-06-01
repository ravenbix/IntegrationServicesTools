function Start-SsisValidationObject
{
    <#
        .SYNOPSIS
            Validates an SSISDB project or package and returns the validation operation id.

        .DESCRIPTION
            Calls Validate() on the supplied ProjectInfo or PackageInfo with the 32-bit runtime flag
            (passed as use32RuntimeOn64), the requested ReferenceUsage, and the optional environment
            reference, then returns the numeric validation operation id. Internal interop helper, not
            exported from the module.

        .EXAMPLE
            $id = Start-SsisValidationObject -Target $project -Reference $null -ReferenceUsage 'UseAllReferences'

            Validates the project against all its environment references and returns the operation id.

        .PARAMETER Target
            The SSISDB ProjectInfo or PackageInfo object to validate, as returned by
            Get-SsisProjectObject or Get-SsisPackageObject.

        .PARAMETER Reference
            The EnvironmentReference to validate against when -ReferenceUsage is SpecifyReference, or
            $null otherwise.

        .PARAMETER ReferenceUsage
            How environment references are applied: UseAllReferences, UseNoReference or SpecifyReference.

        .PARAMETER Use32BitRuntime
            When set, validates in the 32-bit runtime (passed as use32RuntimeOn64).

        .OUTPUTS
            System.Int64
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Start-SsisValidation) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Target,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Reference,

        [Parameter(Mandatory = $true)]
        [ValidateSet('UseAllReferences', 'UseNoReference', 'SpecifyReference')]
        [string]
        $ReferenceUsage,

        [Parameter()]
        [switch]
        $Use32BitRuntime
    )

    process
    {
        $referenceUsageValue = [Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo+ReferenceUsage]$ReferenceUsage

        return $Target.Validate($Use32BitRuntime.IsPresent, $referenceUsageValue, $Reference)
    }
}
