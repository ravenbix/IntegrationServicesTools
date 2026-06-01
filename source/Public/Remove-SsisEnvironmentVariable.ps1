function Remove-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Removes a variable from an SSISDB environment on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and removes a variable from an SSISDB
            environment. Accepts a piped Ssis.EnvironmentVariable object, reaching its environment via
            its Parent. Writes an error when the catalog, folder, environment, or named variable does
            not exist. This is a destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port'

            Removes the Port variable from the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port' | Remove-SsisEnvironmentVariable

            Removes the piped Port variable via its parent environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment whose variable to remove.

        .PARAMETER Environment
            The name of the environment whose variable to remove.

        .PARAMETER InputObject
            A piped Ssis.EnvironmentVariable object to remove, instead of
            -SqlInstance/-Folder/-Environment/-Name, keeping the existing connection from a
            Get-SsisEnvironmentVariable pipeline.

        .PARAMETER Name
            The name of the variable to remove from the environment.

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
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject.Parent
            $variableName = $InputObject.Name

            if ($null -eq $environmentObject)
            {
                Write-Error -Message 'The piped Ssis.EnvironmentVariable object has no parent environment.'
                return
            }
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

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Error -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }

            $variable = Get-SsisEnvironmentVariableObject -Environment $environmentObject -Name $Name

            if ($null -eq $variable)
            {
                Write-Error -Message ('Variable ''{0}'' was not found in environment ''{1}''.' -f $Name, $Environment)
                return
            }

            $variableName = $Name
        }

        if ($PSCmdlet.ShouldProcess($variableName, 'Remove SSIS environment variable'))
        {
            Remove-SsisEnvironmentVariableObject -Environment $environmentObject -Name $variableName
        }
    }
}
