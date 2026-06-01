function Publish-SsisProject
{
    <#
        .SYNOPSIS
            Deploys an .ispac project into a folder of the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance, reads the .ispac file at -Path, and deploys
            it into the target folder. The catalog project name defaults to the .ispac file name
            (without extension) and is overridden by -Name. Accepts a piped Ssis.Folder object as the
            deploy target. The deploy is synchronous; on success the project is re-read and returned as
            an Ssis.Project object. Writes an error and makes no change when the path, catalog, or
            folder does not exist.

        .EXAMPLE
            Publish-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Path 'C:\build\Sales.ispac'

            Deploys Sales.ispac into the Finance folder as the project named Sales.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the existing folder to deploy the project into.

        .PARAMETER InputObject
            A piped Ssis.Folder object to deploy into, instead of -SqlInstance/-Folder, keeping the
            existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Path
            The path to the .ispac project file to deploy into the catalog.

        .PARAMETER Name
            The catalog project name to create or update. Defaults to the .ispac file name without its
            extension when omitted.

        .OUTPUTS
            Ssis.Project
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Project')]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Leaf))
        {
            Write-Error -Message ('The .ispac file ''{0}'' was not found.' -f $Path)
            return
        }

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $projectName = $Name
        }
        else
        {
            $projectName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $targetFolder = $InputObject
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
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''. Create it with New-SsisCatalog.' -f $SqlInstance)
                return
            }

            $targetFolder = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $targetFolder)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($projectName, 'Deploy SSIS project'))
        {
            $projectBytes = Get-Content -Path $Path -Encoding Byte -Raw

            Publish-SsisProjectObject -Folder $targetFolder -Name $projectName -ProjectBytes $projectBytes

            $project = Get-SsisProjectObject -Folder $targetFolder -Name $projectName
            $project | Add-SsisTypeName -TypeName 'Ssis.Project'
        }
    }
}
