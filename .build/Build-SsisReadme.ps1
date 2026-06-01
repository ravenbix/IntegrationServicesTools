function Get-SsisReadmeNounGroup
{
    <#
        .SYNOPSIS
            Maps an SSIS command name to its README index group.

        .DESCRIPTION
            Returns the noun portion (the text after the 'Ssis' prefix) of a
            <Verb>-Ssis<Noun> command name. Any noun beginning with 'Environment'
            (Environment, EnvironmentVariable, EnvironmentReference) collapses to the
            single group 'Environment'.

        .PARAMETER CommandName
            The full command name, for example 'Get-SsisEnvironmentVariable'.

        .EXAMPLE
            Get-SsisReadmeNounGroup -CommandName 'Set-SsisEnvironmentVariable'

            Returns 'Environment'.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $CommandName
    )

    process
    {
        $noun = ($CommandName -split '-Ssis', 2)[1]

        if ($noun -like 'Environment*')
        {
            return 'Environment'
        }

        return $noun
    }
}

function Get-SsisReadmeGroupRank
{
    <#
        .SYNOPSIS
            Returns the sort rank for a README command group.

        .DESCRIPTION
            Known groups sort in workflow precedence (Catalog, Folder, Project,
            Package, Environment, Parameter). Unknown groups sort after all known
            groups, alphabetically by virtue of a shared high rank plus name compare
            done by the caller.

        .PARAMETER Group
            The group name returned by Get-SsisReadmeNounGroup.

        .EXAMPLE
            Get-SsisReadmeGroupRank -Group 'Catalog'

            Returns 0.

        .OUTPUTS
            System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Group
    )

    process
    {
        $order = @('Catalog', 'Folder', 'Project', 'Package', 'Environment', 'Parameter')
        $index = $order.IndexOf($Group)

        if ($index -lt 0)
        {
            return $order.Count
        }

        return $index
    }
}

function Get-SsisReadmeVerbRank
{
    <#
        .SYNOPSIS
            Returns the sort rank for a command verb within a README group.

        .DESCRIPTION
            Orders verbs in a natural lifecycle (Get, New, Set, Publish, Export,
            Start, Stop, Wait, Remove). Unknown verbs sort after all known verbs.

        .PARAMETER Verb
            The verb portion of a command name, for example 'Get'.

        .EXAMPLE
            Get-SsisReadmeVerbRank -Verb 'Get'

            Returns 0.

        .OUTPUTS
            System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Verb
    )

    process
    {
        $order = @('Get', 'New', 'Set', 'Publish', 'Export', 'Start', 'Stop', 'Wait', 'Remove')
        $index = $order.IndexOf($Verb)

        if ($index -lt 0)
        {
            return $order.Count
        }

        return $index
    }
}
