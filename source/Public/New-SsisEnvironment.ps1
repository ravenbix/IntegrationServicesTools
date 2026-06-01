function New-SsisEnvironment
{
    <#
        .SYNOPSIS
            Creates an environment in a folder of the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and creates an environment in the target
            folder. Accepts a piped Ssis.Folder object as the target. Writes an error and makes no change
            when an environment with the same name already exists, or when the catalog or folder does not
            exist. Returns the new environment as an Ssis.Environment object.

        .EXAMPLE
            New-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' -Description 'Production'

            Creates the Prod environment in the Finance folder on the named instance, with a
            description.

        .EXAMPLE
            New-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod'

            Creates the Prod environment with no description (the default empty string when
            -Description is omitted).

        .EXAMPLE
            New-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' -WhatIf

            Reports that the Prod environment would be created without making any change, then
            returns.

        .EXAMPLE
            $cred = Get-Credential
            New-SsisEnvironment -SqlInstance 'SQL01\PROD' -SqlCredential $cred -Folder 'Finance' -Name 'Prod'

            Connects with SQL Server authentication using the supplied credential and creates the
            Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' | New-SsisEnvironment -Name 'Prod'

            Creates the Prod environment in the piped Finance folder (the ByObject parameter set,
            reusing the folder's existing connection).

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' |
                New-SsisEnvironment -Name 'Prod' -Description 'Production'

            Creates the Prod environment with a description in the piped Finance folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the existing folder to create the environment in.

        .PARAMETER InputObject
            A piped Ssis.Folder object to create the environment in, instead of -SqlInstance/-Folder,
            keeping the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of the environment to create within the folder.

        .PARAMETER Description
            An optional description stored on the environment. Defaults to an empty string when omitted.

        .OUTPUTS
            Ssis.Environment
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Description = ''
    )

    process
    {
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

        if ($null -ne (Get-SsisEnvironmentObject -Folder $targetFolder -Name $Name))
        {
            Write-Error -Message ('An environment named ''{0}'' already exists in the folder.' -f $Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create SSIS environment'))
        {
            $environment = New-SsisEnvironmentObject -Folder $targetFolder -Name $Name -Description $Description
            $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
        }
    }
}
