function Get-SsisReadmeNounGroup
{
    <#
        .SYNOPSIS
            Maps an SSIS command name to its README index group.

        .DESCRIPTION
            Returns the noun portion (the text after the 'Ssis' prefix) of a
            <Verb>-Ssis<Noun> command name. Any noun beginning with 'Environment'
            (Environment, EnvironmentVariable, EnvironmentReference) collapses to the
            single group 'Environment'. Throws if the supplied name does not contain
            the '-Ssis' segment (i.e. is not a <Verb>-Ssis<Noun> command).

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

        if ([string]::IsNullOrEmpty($noun))
        {
            throw "Command name '$CommandName' is not a <Verb>-Ssis<Noun> command."
        }

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

function Get-SsisReadmeCommandInfo
{
    <#
        .SYNOPSIS
            Extracts command name, verb, group, and synopsis from a public source file.

        .DESCRIPTION
            Parses a PowerShell source file with the language AST and reads the
            function's comment-based help synopsis. Returns a single object carrying
            the data the README index needs, including the source file Path so the
            index can link each command to its definition. Files that contain no
            function definition are ignored (no output).

        .PARAMETER Path
            Full path to a *.ps1 file under source/Public.

        .EXAMPLE
            Get-SsisReadmeCommandInfo -Path 'source/Public/Get-SsisFolder.ps1'

            Returns an object with Name, Verb, Group, Synopsis, and Path.

        .OUTPUTS
            PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    process
    {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $Path
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($raw, [ref] $null, [ref] $null)

        $functionAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Select-Object -First 1

        if (-not $functionAst)
        {
            return
        }

        $name = $functionAst.Name
        $synopsis = ($functionAst.GetHelpContent().Synopsis -replace '\s+', ' ').Trim()
        $verb = ($name -split '-', 2)[0]

        [PSCustomObject]@{
            Name     = $name
            Verb     = $verb
            Group    = Get-SsisReadmeNounGroup -CommandName $name
            Synopsis = $synopsis
            Path     = $Path
        }
    }
}

function ConvertTo-SsisReadme
{
    <#
        .SYNOPSIS
            Builds the full README text from the template and the public command set.

        .DESCRIPTION
            Reads the README template, enumerates the public command source files,
            assembles a command-reference index grouped by SSIS noun (Environment
            variants collapsed) with a total count, links each command name to its
            public source file (relative to the template/README directory), and
            substitutes the index for the <!-- SSIS:COMMANDS --> token. Returns the
            complete README text. Pure: it performs no writes. Throws if the template
            lacks the token.

        .PARAMETER TemplatePath
            Path to README.template.md.

        .PARAMETER SourcePath
            Path to the folder of public command *.ps1 files (source/Public).

        .EXAMPLE
            ConvertTo-SsisReadme -TemplatePath './README.template.md' -SourcePath './source/Public'

            Returns the generated README text.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]
        $SourcePath
    )

    process
    {
        $token = '<!-- SSIS:COMMANDS -->'
        $template = Get-Content -Raw -Encoding UTF8 -Path $TemplatePath

        # Source-file links are written relative to the README, which sits beside the template.
        $baseDir = Split-Path -Path $TemplatePath -Parent

        if (-not $template.Contains($token))
        {
            throw "README template '$TemplatePath' does not contain the $token placeholder."
        }

        $commands = @(
            Get-ChildItem -Path $SourcePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                ForEach-Object -Process { Get-SsisReadmeCommandInfo -Path $_.FullName }
        )

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('## Command reference')
        $lines.Add('')
        $lines.Add("IntegrationServicesTools exposes $($commands.Count) commands.")

        $groupSort = @(
            @{ Expression = { Get-SsisReadmeGroupRank -Group $_.Name } },
            @{ Expression = { $_.Name } }
        )

        $verbSort = @(
            @{ Expression = { Get-SsisReadmeVerbRank -Verb $_.Verb } },
            @{ Expression = { $_.Name } }
        )

        $groups = $commands |
            Group-Object -Property Group |
                Sort-Object -Property $groupSort

        foreach ($group in $groups)
        {
            $lines.Add('')
            $lines.Add("### $($group.Name)")
            $lines.Add('')
            $lines.Add('| Command | Synopsis |')
            $lines.Add('| --- | --- |')

            $ordered = $group.Group |
                Sort-Object -Property $verbSort

            foreach ($command in $ordered)
            {
                # Escape any literal pipe in a synopsis so it cannot break the Markdown table cell.
                $cell = $command.Synopsis -replace '\|', '\|'

                # Link the command name to its public source file, relative to the README.
                if ($command.Path.StartsWith($baseDir, [System.StringComparison]::OrdinalIgnoreCase))
                {
                    $relative = $command.Path.Substring($baseDir.Length).TrimStart('\', '/')
                }
                else
                {
                    $relative = Split-Path -Path $command.Path -Leaf
                }

                $relative = $relative -replace '\\', '/'

                $lines.Add("| **[$($command.Name)]($relative)** | $cell |")
            }
        }

        $block = $lines -join "`n"

        return $template.Replace($token, $block)
    }
}

function Update-SsisReadme
{
    <#
        .SYNOPSIS
            Generates and writes README.md from the template and public command set.

        .DESCRIPTION
            Calls ConvertTo-SsisReadme and writes the result to the output path as
            UTF-8 without a byte-order mark (matching the repository encoding). This
            is the only side-effecting function in the README generator.

        .PARAMETER TemplatePath
            Path to README.template.md.

        .PARAMETER SourcePath
            Path to the folder of public command *.ps1 files (source/Public).

        .PARAMETER OutputPath
            Path to write the generated README.md.

        .EXAMPLE
            Update-SsisReadme -TemplatePath './README.template.md' -SourcePath './source/Public' -OutputPath './README.md'

            Regenerates README.md in place.

        .OUTPUTS
            None.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [string]
        $OutputPath
    )

    process
    {
        $splatReadme = @{
            TemplatePath = $TemplatePath
            SourcePath   = $SourcePath
        }

        $content = ConvertTo-SsisReadme @splatReadme

        $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

        if ($PSCmdlet.ShouldProcess($resolvedOutput, 'Write generated README'))
        {
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($resolvedOutput, $content, $utf8NoBom)
        }
    }
}
