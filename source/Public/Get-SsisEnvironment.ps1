function Get-SsisEnvironment
{
    <#
        .SYNOPSIS
            Gets environments from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB environments as
            Ssis.Environment objects. Returns every environment across all folders by default, the
            environments of one folder when -Folder is given, or a single environment when -Name is also
            given. Accepts a piped Ssis.Folder object to list that folder's environments without
            reconnecting. Writes a warning and returns nothing when the catalog or named folder does not
            exist.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance'

            Returns the environments in the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' | Get-SsisEnvironment

            Returns every environment in every folder by piping folder objects in.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder whose environments to return. When omitted, environments from every
            folder in the catalog are returned.

        .PARAMETER InputObject
            A piped Ssis.Folder object whose environments to list. Used instead of -SqlInstance/-Folder
            to keep the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of a specific environment to return. When omitted, all environments in scope are
            returned.

        .OUTPUTS
            Ssis.Environment
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Environment')]
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
        $environmentParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $environmentParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environments = Get-SsisEnvironmentObject -Folder $InputObject @environmentParameters

            foreach ($environment in $environments)
            {
                if ($null -ne $environment)
                {
                    $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
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
            $environments = Get-SsisEnvironmentObject -Folder $catalogFolder @environmentParameters

            foreach ($environment in $environments)
            {
                if ($null -ne $environment)
                {
                    $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
                }
            }
        }
    }
}
