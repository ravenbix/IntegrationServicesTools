function New-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Creates an environment reference from an SSISDB project to an environment.

        .DESCRIPTION
            Connects to the specified SQL Server instance and adds an environment reference to a project.
            When -EnvironmentFolder is omitted a relative reference (to an environment in the project's
            own folder) is created; when supplied an absolute reference to that folder's environment is
            created. Accepts a piped Ssis.Project object as the target. Writes an error and makes no
            change when a matching reference already exists, or when the catalog, folder, or project does
            not exist. Returns the new reference as an Ssis.EnvironmentReference object.

        .EXAMPLE
            New-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Environment 'Prod'

            Creates a relative reference from the Sales project to the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | New-SsisEnvironmentReference -Environment 'Prod' -EnvironmentFolder 'Shared'

            Creates an absolute reference from the piped project to the Prod environment in the Shared folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to add the reference to.

        .PARAMETER Project
            The name of the project to add the environment reference to.

        .PARAMETER InputObject
            A piped Ssis.Project object to add the reference to, instead of -SqlInstance/-Folder/-Project,
            keeping the existing connection from a Get-SsisProject pipeline.

        .PARAMETER Environment
            The name of the environment to reference from the project.

        .PARAMETER EnvironmentFolder
            The folder of the environment for an absolute reference. Omit for a relative reference to an
            environment in the project's own folder.

        .OUTPUTS
            Ssis.EnvironmentReference
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentReference')]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Environment,

        [Parameter()]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projectObject = $InputObject
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
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }
        }

        $folderBound = $PSBoundParameters.ContainsKey('EnvironmentFolder')

        # A relative reference (no folder bound) reports its EnvironmentFolderName as '.' in the
        # catalog, not as an empty string, so the relative match accepts both.
        $existing = Get-SsisEnvironmentReferenceObject -Project $projectObject |
            Where-Object -FilterScript {
                $_.Name -eq $Environment -and
                (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                 (-not $folderBound -and ([string]::IsNullOrEmpty($_.EnvironmentFolderName) -or $_.EnvironmentFolderName -eq '.')))
            }

        if ($null -ne $existing)
        {
            Write-Error -Message ('An environment reference to ''{0}'' already exists on project ''{1}''.' -f $Environment, $projectObject.Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Environment, 'Create SSIS environment reference'))
        {
            $referenceParameters = @{
                Project     = $projectObject
                Environment = $Environment
            }

            if ($folderBound)
            {
                $referenceParameters['EnvironmentFolder'] = $EnvironmentFolder
            }

            New-SsisEnvironmentReferenceObject @referenceParameters

            $new = Get-SsisEnvironmentReferenceObject -Project $projectObject |
                Where-Object -FilterScript {
                    $_.Name -eq $Environment -and
                    (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                     (-not $folderBound -and ([string]::IsNullOrEmpty($_.EnvironmentFolderName) -or $_.EnvironmentFolderName -eq '.')))
                }

            $new | Add-SsisTypeName -TypeName 'Ssis.EnvironmentReference'
        }
    }
}
