function Get-SsisParameter
{
    <#
        .SYNOPSIS
            Gets parameters from a project or package in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB parameters as Ssis.Parameter
            objects. Returns the project's parameters by default, or a package's parameters when -Package
            is given, narrowing to a single parameter with -Name. Accepts a piped Ssis.Project or
            Ssis.Package object to list its parameters without reconnecting. Writes a warning and returns
            nothing when the catalog, folder, project, or named package does not exist.

        .EXAMPLE
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the project-level parameters of the Sales project.

        .EXAMPLE
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort'

            Returns just the TargetPort project-level parameter. Writes a warning and returns nothing
            when no parameter of that name exists.

        .EXAMPLE
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'

            Returns the package-level parameters of the Load.dtsx package instead of the project-level
            parameters.

        .EXAMPLE
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Name 'BatchSize'

            Returns just the BatchSize parameter of the Load.dtsx package.

        .EXAMPLE
            $cred = Get-Credential
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Folder 'Finance' -Project 'Sales'

            Connects with SQL Server authentication using the supplied credential and returns the
            project-level parameters of the Sales project.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | Get-SsisParameter

            Returns the project-level parameters of the piped Sales project.

        .EXAMPLE
            Get-SsisPackage -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'Load.dtsx' | Get-SsisParameter -Name 'BatchSize'

            Returns the BatchSize parameter of the piped Load.dtsx package without reconnecting.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose parameters to return.

        .PARAMETER Project
            The name of the project whose parameters to return.

        .PARAMETER Package
            The name of a package within the project whose parameters to return. When omitted,
            project-level parameters are returned.

        .PARAMETER InputObject
            A piped Ssis.Project or Ssis.Package object whose parameters to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject or
            Get-SsisPackage pipeline.

        .PARAMETER Name
            The name of a specific parameter to return. When omitted, all parameters in scope are returned.

        .OUTPUTS
            Ssis.Parameter
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
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

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $parameterParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $parameterParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $container = $InputObject
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
        }

        $parameters = Get-SsisParameterObject -Container $container @parameterParameters

        foreach ($parameter in $parameters)
        {
            if ($null -ne $parameter)
            {
                $parameter | Add-SsisTypeName -TypeName 'Ssis.Parameter'
            }
        }
    }
}
