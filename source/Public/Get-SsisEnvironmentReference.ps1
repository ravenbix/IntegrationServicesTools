function Get-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Gets the environment references defined on an SSISDB project.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the environment references of an
            SSISDB project as Ssis.EnvironmentReference objects. Each reference binds the project to an
            environment (relative to the project's folder, or absolute to a named folder). Accepts a
            piped Ssis.Project object to list its references without reconnecting. Writes a warning and
            returns nothing when the catalog, folder, or named project does not exist.

        .EXAMPLE
            Get-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the environment references defined on the Sales project.

        .EXAMPLE
            $cred = Get-Credential
            Get-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Folder 'Finance' -Project 'Sales'

            Connects with SQL Server authentication using the supplied credential and returns the
            environment references of the Sales project.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | Get-SsisEnvironmentReference

            Returns the environment references of the piped Sales project.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose references to return.

        .PARAMETER Project
            The name of the project whose environment references to return.

        .PARAMETER InputObject
            A piped Ssis.Project object whose references to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject pipeline.

        .OUTPUTS
            Ssis.EnvironmentReference
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
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
        $InputObject
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
        }

        $references = Get-SsisEnvironmentReferenceObject -Project $projectObject

        foreach ($reference in $references)
        {
            if ($null -ne $reference)
            {
                $reference | Add-SsisTypeName -TypeName 'Ssis.EnvironmentReference'
            }
        }
    }
}
