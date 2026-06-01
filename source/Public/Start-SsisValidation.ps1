function Start-SsisValidation
{
    <#
        .SYNOPSIS
            Validates an SSISDB project or package.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Project or Ssis.Package)
            and validates the target, returning the validation Ssis.Operation. Omit -Package to validate
            the whole project; supply it to validate one package. Environment references are applied by
            inference: -EnvironmentName validates against that single reference (SpecifyReference),
            -NoReference validates ignoring references (UseNoReference), and supplying neither validates
            against all references (UseAllReferences). With -Synchronous, waits for the validation to
            finish (honouring -PollInterval and -Timeout) via Wait-SsisOperation and returns the
            completed operation. Writes a warning and makes no change when the catalog, folder, project,
            package, or named environment reference does not exist.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Confirm:$false

            Validates the whole Sales project against all its environment references.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Synchronous -Confirm:$false

            Validates one package against the Prod environment reference and waits for the result.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -NoReference -Confirm:$false

            Validates the project while ignoring all environment references (UseNoReference).

        .EXAMPLE
            $splatValidation = @{
                SqlInstance       = 'SQL01\PROD'
                Folder            = 'Finance'
                Project           = 'Sales'
                EnvironmentName   = 'Prod'
                EnvironmentFolder = 'Shared'
                Confirm           = $false
            }
            Start-SsisValidation @splatValidation

            Validates against the 'Prod' environment reference that points at the 'Shared' folder,
            disambiguating when several references share the name 'Prod'.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Use32BitRuntime -Confirm:$false

            Validates the project in the 32-bit runtime, for packages needing a 32-bit provider or
            driver.

        .EXAMPLE
            $splatSyncValidation = @{
                SqlInstance  = 'SQL01\PROD'
                Folder       = 'Finance'
                Project      = 'Sales'
                Synchronous  = $true
                PollInterval = 2
                Timeout      = 60
                Confirm      = $false
            }
            Start-SsisValidation @splatSyncValidation

            Validates the project and waits up to 60 seconds for it to finish, refreshing status every
            2 seconds.

        .EXAMPLE
            $cred = Get-Credential
            $splatCredValidation = @{
                SqlInstance   = 'SQL01\PROD'
                SqlCredential = $cred
                Folder        = 'Finance'
                Project       = 'Sales'
                Confirm       = $false
            }
            Start-SsisValidation @splatCredValidation

            Connects with SQL Server authentication using the supplied credential and validates the
            project.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | Start-SsisValidation -Confirm:$false

            Pipes a project in (the ByObject parameter set) and validates it without reconnecting.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -WhatIf

            Shows what would be validated without starting the validation operation.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to validate.

        .PARAMETER Project
            The name of the project to validate (or whose package is validated).

        .PARAMETER Package
            The name of a single package to validate. When omitted, the whole project is validated.

        .PARAMETER InputObject
            A piped Ssis.Project or Ssis.Package object to validate, used instead of
            -SqlInstance/-Folder/-Project/-Package to keep the existing connection.

        .PARAMETER EnvironmentName
            The name of an environment reference on the project to validate against (SpecifyReference).
            Mutually exclusive with -NoReference.

        .PARAMETER EnvironmentFolder
            The folder of the environment when the reference is to an environment in a different folder
            than the project. When omitted, a reference named -EnvironmentName is matched regardless of
            folder.

        .PARAMETER NoReference
            Validates ignoring all environment references (UseNoReference). Mutually exclusive with
            -EnvironmentName.

        .PARAMETER Use32BitRuntime
            Validates in the 32-bit runtime (for packages needing a 32-bit provider or driver).

        .PARAMETER Synchronous
            Waits for the validation operation to reach a terminal state before returning it.

        .PARAMETER PollInterval
            With -Synchronous, seconds between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            With -Synchronous, maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Operation
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Operation')]
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
        $EnvironmentName,

        [Parameter()]
        [string]
        $EnvironmentFolder,

        [Parameter()]
        [switch]
        $NoReference,

        [Parameter()]
        [switch]
        $Use32BitRuntime,

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
        if ($PSBoundParameters.ContainsKey('EnvironmentName') -and $NoReference)
        {
            throw 'Specify either -EnvironmentName or -NoReference, not both.'
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $target = $InputObject

            if ($InputObject.PSObject.TypeNames -contains 'Ssis.Package')
            {
                $projectObject = $InputObject.Parent
            }
            else
            {
                $projectObject = $InputObject
            }

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

            if ($PSBoundParameters.ContainsKey('Package'))
            {
                $packageObject = Get-SsisPackageObject -Project $projectObject -Name $Package

                if ($null -eq $packageObject)
                {
                    Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                    return
                }

                $target = $packageObject
            }
            else
            {
                $target = $projectObject
            }
        }

        $reference = $null
        $referenceUsage = 'UseAllReferences'

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

            $referenceUsage = 'SpecifyReference'
        }
        elseif ($NoReference)
        {
            $referenceUsage = 'UseNoReference'
        }

        if (-not $PSCmdlet.ShouldProcess($target.Name, 'Start SSIS validation'))
        {
            return
        }

        $splatValidate = @{
            Target         = $target
            Reference      = $reference
            ReferenceUsage = $referenceUsage
        }

        if ($Use32BitRuntime)
        {
            $splatValidate['Use32BitRuntime'] = $true
        }

        $operationId = Start-SsisValidationObject @splatValidate

        # ByObject left the catalog unresolved: walk up from the project (project.Parent = folder,
        # folder.Parent = catalog). Two hops, vs Start-SsisExecution's three from the package.
        if ($null -eq $catalog)
        {
            $catalog = $projectObject.Parent.Parent
        }

        $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $operationId

        if ($Synchronous)
        {
            $operation | Wait-SsisOperation -PollInterval $PollInterval -Timeout $Timeout
        }
        else
        {
            $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
        }
    }
}
