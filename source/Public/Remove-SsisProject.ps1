function Remove-SsisProject
{
    <#
        .SYNOPSIS
            Removes a project from a folder in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and drops a project (and its packages) from
            the SSISDB catalog. Accepts a piped Ssis.Project object to drop without reconnecting.
            Writes an error when the catalog, folder, or named project does not exist. This is a
            destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales'

            Removes the Sales project from the Finance folder on the named instance.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder that contains the project to remove.

        .PARAMETER Name
            The name of the project to remove from the folder.

        .PARAMETER InputObject
            A piped Ssis.Project object to drop, instead of -SqlInstance/-Folder/-Name, keeping the
            existing connection from a Get-SsisProject pipeline.

        .OUTPUTS
            [void]
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
        $Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject
    )

    process
    {
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

        if ($PSCmdlet.ShouldProcess($project.Name, 'Remove SSIS project'))
        {
            Remove-SsisProjectObject -Project $project
        }
    }
}
