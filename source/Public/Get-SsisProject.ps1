function Get-SsisProject
{
    <#
        .SYNOPSIS
            Gets projects from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB catalog projects as
            Ssis.Project objects. Returns every project across all folders by default, the projects of
            one folder when -Folder is given, or a single project when -Name is also given. Accepts a
            piped Ssis.Folder object to list that folder's projects without reconnecting. Writes a
            warning and returns nothing when the catalog or named folder does not exist.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance'

            Returns the projects in the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' | Get-SsisProject

            Returns every project in every folder by piping folder objects in.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder whose projects to return. When omitted, projects from every folder
            in the catalog are returned.

        .PARAMETER InputObject
            A piped Ssis.Folder object whose projects to list. Used instead of -SqlInstance/-Folder to
            keep the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of a specific project to return. When omitted, all projects in scope are returned.

        .OUTPUTS
            Ssis.Project
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
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

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $projectParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $projectParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projects = Get-SsisProjectObject -Folder $InputObject @projectParameters

            foreach ($project in $projects)
            {
                if ($null -ne $project)
                {
                    $project | Add-SsisTypeName -TypeName 'Ssis.Project'
                }
            }

            return
        }

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

        if ($PSBoundParameters.ContainsKey('Folder'))
        {
            $folders = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folders)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }
        }
        else
        {
            $folders = Get-SsisFolderObject -Catalog $catalog
        }

        foreach ($catalogFolder in $folders)
        {
            $projects = Get-SsisProjectObject -Folder $catalogFolder @projectParameters

            foreach ($project in $projects)
            {
                if ($null -ne $project)
                {
                    $project | Add-SsisTypeName -TypeName 'Ssis.Project'
                }
            }
        }
    }
}
