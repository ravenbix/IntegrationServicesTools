function Get-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Gets variables from an environment in the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the variables of an SSISDB
            environment as Ssis.EnvironmentVariable objects, or a single variable when -Name is given.
            Accepts a piped Ssis.Environment object to list its variables without reconnecting. Writes a
            warning and returns nothing when the catalog, folder, named environment, or named variable
            does not exist. Sensitive variable values are returned masked by the server.

        .EXAMPLE
            Get-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod'

            Returns the variables of the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port'

            Returns just the Port variable from the Prod environment. Writes a warning and returns
            nothing when no variable of that name exists.

        .EXAMPLE
            $cred = Get-Credential
            $splatGetVariable = @{
                SqlInstance   = 'SQL01\PROD'
                SqlCredential = $cred
                Folder        = 'Finance'
                Environment   = 'Prod'
            }
            Get-SsisEnvironmentVariable @splatGetVariable

            Connects with SQL Server authentication using the supplied credential and returns every
            variable in the Prod environment.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Get-SsisEnvironmentVariable

            Returns the variables of the piped Prod environment.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Get-SsisEnvironmentVariable -Name 'Port'

            Returns just the Port variable of the piped Prod environment, reusing the existing
            connection.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment whose variables to return.

        .PARAMETER Environment
            The name of the environment whose variables to return.

        .PARAMETER InputObject
            A piped Ssis.Environment object whose variables to list. Used instead of
            -SqlInstance/-Folder/-Environment to keep the existing connection from a Get-SsisEnvironment
            pipeline.

        .PARAMETER Name
            The name of a specific variable to return. When omitted, all variables in the environment are
            returned.

        .OUTPUTS
            Ssis.EnvironmentVariable
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentVariable')]
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
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $variableParameters = @{}
        $found = $false

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $variableParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject
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

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Warning -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }
        }

        $variables = Get-SsisEnvironmentVariableObject -Environment $environmentObject @variableParameters

        foreach ($variable in $variables)
        {
            if ($null -ne $variable)
            {
                $found = $true
                $variable | Add-SsisTypeName -TypeName 'Ssis.EnvironmentVariable'
            }
        }

        if ($PSBoundParameters.ContainsKey('Name') -and -not $found)
        {
            Write-Warning -Message ('Variable ''{0}'' was not found in the environment.' -f $Name)
        }
    }
}
