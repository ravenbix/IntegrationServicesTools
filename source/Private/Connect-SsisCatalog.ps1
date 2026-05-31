function Connect-SsisCatalog
{
    <#
        .SYNOPSIS
            Connects to a SQL Server instance and returns its SSIS IntegrationServices object.

        .DESCRIPTION
            Resolves SqlInstance and optional SqlCredential into a
            Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices object. A plain
            instance name becomes an SMO Server (Windows integrated authentication unless a
            credential is supplied); an existing SMO Server or IntegrationServices object is reused.
            Internal helper, not exported from the module.

        .EXAMPLE
            $integrationServices = Connect-SsisCatalog -SqlInstance 'SQL01\PROD'

            Connects to the named instance using the current Windows identity.

        .PARAMETER SqlInstance
            The target SQL Server instance name (for example 'SQL01\PROD'), or an already-built SMO
            Server or IntegrationServices object to reuse instead of opening a new connection.

        .PARAMETER SqlCredential
            A PSCredential used for SQL Server authentication. When omitted, the current Windows
            identity is used (integrated authentication).
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $SqlInstance,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $SqlCredential
    )

    process
    {
        $typeName = $SqlInstance.PSObject.TypeNames[0]

        if ($typeName -eq 'Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices')
        {
            return $SqlInstance
        }

        if ($typeName -eq 'Microsoft.SqlServer.Management.Smo.Server')
        {
            return [Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices]::new($SqlInstance)
        }

        $serverConnection = [Microsoft.SqlServer.Management.Common.ServerConnection]::new([string] $SqlInstance)

        if ($PSBoundParameters.ContainsKey('SqlCredential') -and $SqlCredential)
        {
            $serverConnection.LoginSecure = $false
            $serverConnection.Login = $SqlCredential.UserName
            $serverConnection.SecurePassword = $SqlCredential.Password
        }

        $server = [Microsoft.SqlServer.Management.Smo.Server]::new($serverConnection)

        return [Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices]::new($server)
    }
}
