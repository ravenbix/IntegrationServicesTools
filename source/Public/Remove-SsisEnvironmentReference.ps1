function Remove-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Removes an environment reference from an SSISDB project.

        .DESCRIPTION
            Connects to the specified SQL Server instance and removes the environment reference matching
            -Environment (and -EnvironmentFolder, when given) from a project. Accepts a piped
            Ssis.EnvironmentReference object, reaching its project via its Parent. Writes an error when no
            matching reference exists, or when the catalog, folder, or project does not exist. This is a
            destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Environment 'Prod'

            Removes the relative reference to the Prod environment from the Sales project.

        .EXAMPLE
            Get-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' | Remove-SsisEnvironmentReference

            Removes each piped environment reference from its project.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose reference to remove.

        .PARAMETER Project
            The name of the project whose environment reference to remove.

        .PARAMETER InputObject
            A piped Ssis.EnvironmentReference object to remove, instead of
            -SqlInstance/-Folder/-Project/-Environment, keeping the existing connection from a
            Get-SsisEnvironmentReference pipeline.

        .PARAMETER Environment
            The name of the referenced environment identifying which reference to remove.

        .PARAMETER EnvironmentFolder
            The environment's folder, identifying an absolute reference. Omit to match the relative
            reference to that environment.

        .OUTPUTS
            None
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByInstance')]
    [OutputType([void])]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Environment,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projectObject = $InputObject.Parent
            $reference = $InputObject
            $environmentName = $InputObject.Name
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

            $folderBound = $PSBoundParameters.ContainsKey('EnvironmentFolder')

            $reference = Get-SsisEnvironmentReferenceObject -Project $projectObject |
                Where-Object -FilterScript {
                    $_.Name -eq $Environment -and
                    (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                     (-not $folderBound -and [string]::IsNullOrEmpty($_.EnvironmentFolderName)))
                }

            if ($null -eq $reference)
            {
                Write-Error -Message ('No environment reference to ''{0}'' was found on project ''{1}''.' -f $Environment, $Project)
                return
            }

            $environmentName = $Environment
        }

        if ($PSCmdlet.ShouldProcess($environmentName, 'Remove SSIS environment reference'))
        {
            Remove-SsisEnvironmentReferenceObject -Project $projectObject -Reference $reference
        }
    }
}
