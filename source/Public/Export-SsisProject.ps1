function Export-SsisProject
{
    <#
        .SYNOPSIS
            Exports an SSISDB project to an .ispac file on disk.

        .DESCRIPTION
            Connects to the specified SQL Server instance, retrieves a project's .ispac content, and
            writes it into the -Path directory as <project>.ispac. Accepts a piped Ssis.Project object
            to export without reconnecting. Errors when the target file already exists unless -Force is
            given. Returns the written file as a System.IO.FileInfo object. Writes an error and makes no
            change when the directory, catalog, folder, or project does not exist.

        .EXAMPLE
            Export-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' -Path 'C:\backup'

            Writes C:\backup\Sales.ispac from the Sales project in the Finance folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder that contains the project to export.

        .PARAMETER Name
            The name of the project to export from the folder.

        .PARAMETER InputObject
            A piped Ssis.Project object to export, instead of -SqlInstance/-Folder/-Name, keeping the
            existing connection from a Get-SsisProject pipeline.

        .PARAMETER Path
            The existing directory to write the <project>.ispac file into.

        .PARAMETER Force
            Overwrite the target .ispac file if it already exists. Without this switch an existing file
            causes an error and no write.

        .OUTPUTS
            System.IO.FileInfo
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType([System.IO.FileInfo])]
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
        $Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [switch]
        $Force
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Container))
        {
            Write-Error -Message ('The output directory ''{0}'' was not found.' -f $Path)
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $project = $InputObject
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

            $catalogFolder = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $catalogFolder)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $project = Get-SsisProjectObject -Folder $catalogFolder -Name $Name

            if ($null -eq $project)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Name, $Folder)
                return
            }
        }

        $targetFile = Join-Path -Path $Path -ChildPath ($project.Name + '.ispac')

        if ((Test-Path -Path $targetFile -PathType Leaf) -and -not $Force)
        {
            Write-Error -Message ('The file ''{0}'' already exists. Use -Force to overwrite.' -f $targetFile)
            return
        }

        if ($PSCmdlet.ShouldProcess($targetFile, 'Export SSIS project'))
        {
            $projectBytes = Export-SsisProjectObject -Project $project

            $splatContent = @{
                Path     = $targetFile
                Value    = $projectBytes
                Encoding = 'Byte'
            }
            Set-Content @splatContent

            [System.IO.FileInfo]::new($targetFile)
        }
    }
}
