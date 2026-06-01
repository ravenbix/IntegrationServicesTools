function ConvertTo-SsisTypeCode
{
    <#
        .SYNOPSIS
            Resolves a System.TypeCode for an SSISDB environment variable from a value or a name.

        .DESCRIPTION
            Returns the System.TypeCode the SSIS object model needs when adding an environment variable.
            When -DataType is supplied it is looked up (case-insensitively) against the SSIS-supported
            type names. Otherwise the type code is inferred from the supplied value's .NET type, falling
            back to String for a null value. Pure helper with no object-model calls; not exported.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value 42

            Returns [System.TypeCode]::Int32, inferred from the integer value.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value '5' -DataType 'Int32'

            Returns [System.TypeCode]::Int32, forced by the explicit data type name (inference from
            the string value is overridden).

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value 1 -DataType 'int64'

            Returns [System.TypeCode]::Int64. The -DataType name is matched case-insensitively.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value $null

            Returns [System.TypeCode]::String, the fallback used when the value is null and no
            -DataType is supplied.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value $true

            Returns [System.TypeCode]::Boolean, inferred from the .NET type of the supplied value.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value 42 -DataType ''

            Returns [System.TypeCode]::Int32. An empty -DataType is treated as "not supplied", so
            the type code is inferred from the value.

        .OUTPUTS
            System.TypeCode

        .PARAMETER Value
            The value whose .NET type is used to infer the type code when -DataType is not supplied.
            A null value infers String. Ignored when -DataType is given.

        .PARAMETER DataType
            An explicit SSIS data type name (Boolean, Byte, Int16, Int32, Int64, Single, Double,
            Decimal, DateTime, String) that overrides inference. Matched case-insensitively.
    #>
    [CmdletBinding()]
    [OutputType([System.TypeCode])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [string]
        $DataType
    )

    process
    {
        $supported = @{
            'Boolean'  = [System.TypeCode]::Boolean
            'Byte'     = [System.TypeCode]::Byte
            'Int16'    = [System.TypeCode]::Int16
            'Int32'    = [System.TypeCode]::Int32
            'Int64'    = [System.TypeCode]::Int64
            'Single'   = [System.TypeCode]::Single
            'Double'   = [System.TypeCode]::Double
            'Decimal'  = [System.TypeCode]::Decimal
            'DateTime' = [System.TypeCode]::DateTime
            'String'   = [System.TypeCode]::String
        }

        if (-not [string]::IsNullOrEmpty($DataType))
        {
            $match = $supported.Keys | Where-Object -FilterScript { $_ -eq $DataType }

            if ($null -eq $match)
            {
                throw ('Unsupported data type ''{0}''. Valid values: {1}.' -f $DataType, (($supported.Keys | Sort-Object) -join ', '))
            }

            return $supported[$match]
        }

        if ($null -eq $Value)
        {
            return [System.TypeCode]::String
        }

        return [System.Type]::GetTypeCode($Value.GetType())
    }
}
