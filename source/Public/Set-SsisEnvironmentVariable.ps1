function Set-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Adds or updates a variable on an SSISDB environment.

        .DESCRIPTION
            Connects to the specified SQL Server instance and adds or updates a variable on an SSISDB
            environment (upsert: updates the value when the variable exists, otherwise creates it). The
            variable's data type is inferred from the supplied value's .NET type and can be overridden by
            -DataType. -Sensitive stores the value encrypted on the server. Accepts a piped
            Ssis.Environment object as the target. Writes a warning and makes no change when the catalog,
            folder, or environment does not exist. Returns the resulting Ssis.EnvironmentVariable.

        .EXAMPLE
            Set-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1433

            Adds or updates the Int32 Port variable on the Prod environment.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Set-SsisEnvironmentVariable -Name 'Password' -Value 'secret' -Sensitive

            Adds or updates a sensitive Password variable on the piped Prod environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the target environment.

        .PARAMETER Environment
            The name of the environment to add or update the variable on.

        .PARAMETER InputObject
            A piped Ssis.Environment object to set the variable on, instead of
            -SqlInstance/-Folder/-Environment, keeping the existing connection from a Get-SsisEnvironment
            pipeline.

        .PARAMETER Name
            The name of the variable to add or update on the environment.

        .PARAMETER Value
            The value to store in the variable. Its data type is inferred from this value unless
            -DataType is given.

        .PARAMETER DataType
            An explicit SSIS data type name (Boolean, Byte, Int16, Int32, Int64, Single, Double, Decimal,
            DateTime, String) that overrides the type inferred from -Value.

        .PARAMETER Sensitive
            Stores the variable value encrypted (sensitive) on the server. Sensitive values are returned
            masked when read back.

        .PARAMETER Description
            An optional description stored on the variable. Defaults to an empty string when omitted.

        .OUTPUTS
            Ssis.EnvironmentVariable
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentVariable')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [ValidateSet('Boolean', 'Byte', 'Int16', 'Int32', 'Int64', 'Single', 'Double', 'Decimal', 'DateTime', 'String')]
        [string]
        $DataType,

        [Parameter()]
        [switch]
        $Sensitive,

        [Parameter()]
        [string]
        $Description = ''
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject
            $environmentName = $environmentObject.Name
        }
        else
        {
            $connectParameters = @{ SqlInstance = $SqlInstance }

            if ($PSBoundParameters.ContainsKey('SqlCredential'))
            {
                $connectParameters['SqlCredential'] = $SqlCredential
            }

            $integrationServices = Connect-SsisCatalog @connectParameters

            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            if ($null -eq $catalog)
            {
                Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Warning -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }

            $environmentName = $Environment
        }

        $typeCodeParameters = @{ Value = $Value }

        if ($PSBoundParameters.ContainsKey('DataType'))
        {
            $typeCodeParameters['DataType'] = $DataType
        }

        $typeCode = ConvertTo-SsisTypeCode @typeCodeParameters

        if ($PSCmdlet.ShouldProcess(('{0} on {1}' -f $Name, $environmentName), 'Set SSIS environment variable'))
        {
            $splatSetVariable = @{
                Environment = $environmentObject
                Name        = $Name
                Value       = $Value
                TypeCode    = $typeCode
                Sensitive   = [bool]$Sensitive
                Description = $Description
            }

            Set-SsisEnvironmentVariableObject @splatSetVariable

            $variable = Get-SsisEnvironmentVariableObject -Environment $environmentObject -Name $Name
            $variable | Add-SsisTypeName -TypeName 'Ssis.EnvironmentVariable'
        }
    }
}
