function Get-SsisExecution
{
    <#
        .SYNOPSIS
            Gets package executions from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB executions as
            Ssis.Execution objects. Returns a single execution when -ExecutionId is given; otherwise
            lists executions, narrowed by -Folder, -Project, -Package and/or -Status. Accepts a piped
            Ssis.Package to list that package's executions without reconnecting. Writes a warning and
            returns nothing when the catalog does not exist.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Returns the execution with id 42.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Running'

            Returns every currently running execution in the catalog.

        .EXAMPLE
            Get-SsisPackage -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'Load.dtsx' | Get-SsisExecution

            Returns the executions of the piped package.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of a single execution to return. When given, the folder/project/package
            filters are ignored.

        .PARAMETER Folder
            The name of the folder to scope to. When omitted, executions across all folders are returned.

        .PARAMETER Project
            The name of the project to scope to. When omitted, executions across all projects are returned.

        .PARAMETER Package
            The name of the package to scope to. When omitted, executions across all packages are returned.

        .PARAMETER InputObject
            A piped Ssis.Package object whose executions to list, used instead of
            -SqlInstance/-Folder/-Project/-Package to keep the existing connection.

        .PARAMETER Status
            Returns only executions in the given status (for example Running, Success, Failed).

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(ParameterSetName = 'ByInstance')]
        [long]
        $ExecutionId,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Project,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateSet('Created', 'Running', 'Canceled', 'Failed', 'Pending', 'UnexpectTerminated', 'Success', 'Stopping', 'Completion')]
        [string]
        $Status
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $inputPackage = $InputObject
            $catalog = $inputPackage.Parent.Parent.Parent
            $folderFilter = $inputPackage.Parent.Parent.Name
            $projectFilter = $inputPackage.Parent.Name
            $packageFilter = $inputPackage.Name
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

            if ($PSBoundParameters.ContainsKey('ExecutionId'))
            {
                $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

                if ($null -eq $execution)
                {
                    Write-Warning -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                    return
                }

                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            $folderFilter = $Folder
            $projectFilter = $Project
            $packageFilter = $Package
        }

        $executions = Get-SsisExecutionObject -Catalog $catalog

        foreach ($execution in $executions)
        {
            if ($null -eq $execution)
            {
                continue
            }

            if ($folderFilter -and $execution.FolderName -ne $folderFilter)
            {
                continue
            }

            if ($projectFilter -and $execution.ProjectName -ne $projectFilter)
            {
                continue
            }

            if ($packageFilter -and $execution.PackageName -ne $packageFilter)
            {
                continue
            }

            if ($PSBoundParameters.ContainsKey('Status') -and $execution.Status.ToString() -ne $Status)
            {
                continue
            }

            $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
        }
    }
}
