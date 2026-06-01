function Get-SsisPackage
{
    <#
        .SYNOPSIS
            Gets packages from projects in the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB project packages as
            Ssis.Package objects. Scope narrows as you supply -Folder, -Project and -Name; omitting
            them enumerates broadly across the catalog. Accepts a piped Ssis.Project object to list
            that project's packages without reconnecting. Writes a warning and returns nothing when the
            catalog or named folder does not exist.

        .EXAMPLE
            Get-SsisPackage -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the packages in the Sales project of the Finance folder.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' | Get-SsisPackage

            Returns the packages of every project piped in from Get-SsisProject.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder to scope to. When omitted, every folder in the catalog is searched.

        .PARAMETER Project
            The name of the project to scope to. When omitted, every project in scope is searched.

        .PARAMETER InputObject
            A piped Ssis.Project object whose packages to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject pipeline.

        .PARAMETER Name
            The name of a specific package to return. When omitted, all packages in scope are returned.

        .OUTPUTS
            Ssis.Package
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Package')]
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

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $packageParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $packageParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $packages = Get-SsisPackageObject -Project $InputObject @packageParameters

            foreach ($package in $packages)
            {
                if ($null -ne $package)
                {
                    $package | Add-SsisTypeName -TypeName 'Ssis.Package'
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
            if ($PSBoundParameters.ContainsKey('Project'))
            {
                $projects = Get-SsisProjectObject -Folder $catalogFolder -Name $Project
            }
            else
            {
                $projects = Get-SsisProjectObject -Folder $catalogFolder
            }

            foreach ($folderProject in $projects)
            {
                if ($null -eq $folderProject)
                {
                    continue
                }

                $packages = Get-SsisPackageObject -Project $folderProject @packageParameters

                foreach ($package in $packages)
                {
                    if ($null -ne $package)
                    {
                        $package | Add-SsisTypeName -TypeName 'Ssis.Package'
                    }
                }
            }
        }
    }
}
