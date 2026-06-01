function Set-SsisParameter
{
    <#
        .SYNOPSIS
            Sets the value of a project or package parameter in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and sets an SSISDB parameter's value, either to
            a literal (-Value) or to a reference to an environment variable (-ReferencedVariable). The two
            are mutually exclusive; supplying both, or neither, is an error. Targets a project-level
            parameter by default, or a package-level parameter when -Package is given. Accepts a piped
            Ssis.Parameter object. Writes a warning and makes no change when the catalog, folder, project,
            package, or named parameter does not exist. Returns the resulting Ssis.Parameter.

        .EXAMPLE
            Set-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1450

            Sets the TargetPort project parameter to the literal value 1450.

        .EXAMPLE
            Set-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -ReferencedVariable 'Port'

            Binds the TargetPort parameter to the Port environment variable.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose parameter to set.

        .PARAMETER Project
            The name of the project whose parameter to set.

        .PARAMETER Package
            The name of a package within the project whose parameter to set. When omitted, a project-level
            parameter is set.

        .PARAMETER InputObject
            A piped Ssis.Parameter object to set, instead of -SqlInstance/-Folder/-Project/-Name, keeping
            the existing connection from a Get-SsisParameter pipeline.

        .PARAMETER Name
            The name of the parameter to set.

        .PARAMETER Value
            The literal value to assign to the parameter. Mutually exclusive with -ReferencedVariable.

        .PARAMETER ReferencedVariable
            The name of an environment variable to bind the parameter to. Mutually exclusive with -Value.

        .OUTPUTS
            Ssis.Parameter
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Parameter')]
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
        $Project,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name,

        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [string]
        $ReferencedVariable
    )

    process
    {
        $hasValue = $PSBoundParameters.ContainsKey('Value')
        $hasReference = $PSBoundParameters.ContainsKey('ReferencedVariable')

        if ($hasValue -eq $hasReference)
        {
            throw 'Specify exactly one of -Value or -ReferencedVariable.'
        }

        if ($hasValue)
        {
            $valueType = 'Literal'
            $effectiveValue = $Value
        }
        else
        {
            $valueType = 'Referenced'
            $effectiveValue = $ReferencedVariable
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $parameter = $InputObject
            $container = $InputObject.Parent

            if ($container.GetType().Name -eq 'PackageInfo')
            {
                $projectObject = $container.Parent
            }
            else
            {
                $projectObject = $container
            }

            $parameterName = $InputObject.Name
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

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Warning -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }

            if ($PSBoundParameters.ContainsKey('Package'))
            {
                $container = Get-SsisPackageObject -Project $projectObject -Name $Package

                if ($null -eq $container)
                {
                    Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                    return
                }
            }
            else
            {
                $container = $projectObject
            }

            $parameter = Get-SsisParameterObject -Container $container -Name $Name

            if ($null -eq $parameter)
            {
                Write-Warning -Message ('Parameter ''{0}'' was not found.' -f $Name)
                return
            }

            $parameterName = $Name
        }

        if ($PSCmdlet.ShouldProcess($parameterName, 'Set SSIS parameter value'))
        {
            $splatSetParameter = @{
                Parameter = $parameter
                ValueType = $valueType
                Value     = $effectiveValue
                Project   = $projectObject
            }

            Set-SsisParameterObject @splatSetParameter

            $updated = Get-SsisParameterObject -Container $container -Name $parameterName
            $updated | Add-SsisTypeName -TypeName 'Ssis.Parameter'
        }
    }
}
