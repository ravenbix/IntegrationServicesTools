function Start-SsisExecution
{
    <#
        .SYNOPSIS
            Starts an SSISDB package execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Package) and starts the
            package, optionally binding an environment reference by name, applying parameter overrides,
            selecting the 32-bit runtime, and setting the logging level. Returns the started
            Ssis.Execution. With -Synchronous, waits for the run to finish (honouring -PollInterval and
            -Timeout) and returns the completed execution. Writes a warning and makes no change when the
            catalog, folder, project, package, or named environment reference does not exist.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false

            Starts the package and returns the running execution.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Parameter @{ TargetPort = 1450 } -LoggingLevel 'Basic' -Synchronous -Confirm:$false

            Starts the package bound to the Prod environment with a parameter override and Basic logging,
            then waits for it to finish.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to run.

        .PARAMETER Project
            The name of the project containing the package to run.

        .PARAMETER Package
            The name of the package to execute.

        .PARAMETER InputObject
            A piped Ssis.Package object to execute, used instead of -SqlInstance/-Folder/-Project/-Package
            to keep the existing connection.

        .PARAMETER EnvironmentName
            The name of an environment reference on the project to bind the execution to, so referenced
            parameters resolve.

        .PARAMETER EnvironmentFolder
            The folder of the environment when the reference is to an environment in a different folder
            than the project. When omitted, a reference named -EnvironmentName is matched regardless of
            folder.

        .PARAMETER Parameter
            A hashtable of parameter name/value overrides applied to this run only.

        .PARAMETER Use32BitRuntime
            Runs the package in the 32-bit runtime (for packages needing a 32-bit provider or driver).

        .PARAMETER LoggingLevel
            The logging level for this run: None, Basic, Performance or Verbose.

        .PARAMETER Synchronous
            Waits for the execution to reach a terminal state before returning the completed execution.

        .PARAMETER PollInterval
            With -Synchronous, seconds between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            With -Synchronous, maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByInstance')]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $EnvironmentName,

        [Parameter()]
        [string]
        $EnvironmentFolder,

        [Parameter()]
        [hashtable]
        $Parameter,

        [Parameter()]
        [switch]
        $Use32BitRuntime,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Performance', 'Verbose')]
        [string]
        $LoggingLevel,

        [Parameter()]
        [switch]
        $Synchronous,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $Timeout = 0
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $packageObject = $InputObject
            $projectObject = $InputObject.Parent
            $catalog = $null
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

            $packageObject = Get-SsisPackageObject -Project $projectObject -Name $Package

            if ($null -eq $packageObject)
            {
                Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                return
            }
        }

        $reference = $null

        if ($PSBoundParameters.ContainsKey('EnvironmentName'))
        {
            $references = Get-SsisEnvironmentReferenceObject -Project $projectObject

            # Capture the folder-filter flag here; $PSBoundParameters inside a Where-Object filter
            # script refers to Where-Object's own bound parameters, not this function's.
            $hasEnvironmentFolder = $PSBoundParameters.ContainsKey('EnvironmentFolder')

            $reference = $references |
                Where-Object -FilterScript {
                    $_.Name -eq $EnvironmentName -and
                    (-not $hasEnvironmentFolder -or $_.EnvironmentFolderName -eq $EnvironmentFolder)
                } |
                Select-Object -First 1

            if ($null -eq $reference)
            {
                Write-Warning -Message ('Environment reference ''{0}'' was not found on project ''{1}''.' -f $EnvironmentName, $projectObject.Name)
                return
            }
        }

        if (-not $PSCmdlet.ShouldProcess($packageObject.Name, 'Start SSIS execution'))
        {
            return
        }

        $splatStart = @{
            Package   = $packageObject
            Reference = $reference
        }

        if ($PSBoundParameters.ContainsKey('Parameter'))
        {
            $splatStart['Parameter'] = $Parameter
        }

        if ($PSBoundParameters.ContainsKey('LoggingLevel'))
        {
            $splatStart['LoggingLevel'] = $LoggingLevel
        }

        if ($Use32BitRuntime)
        {
            $splatStart['Use32BitRuntime'] = $true
        }

        $executionId = Start-SsisExecutionObject @splatStart

        if ($null -eq $catalog)
        {
            $catalog = $packageObject.Parent.Parent.Parent
        }

        $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $executionId

        if ($Synchronous)
        {
            $execution | Wait-SsisExecution -PollInterval $PollInterval -Timeout $Timeout
        }
        else
        {
            $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
        }
    }
}
