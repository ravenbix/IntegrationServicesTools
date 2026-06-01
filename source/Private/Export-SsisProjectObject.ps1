function Export-SsisProjectObject
{
    <#
        .SYNOPSIS
            Returns the .ispac byte content of an SSISDB project.

        .DESCRIPTION
            Calls GetProjectBytes() on the supplied ProjectInfo object and returns the resulting
            byte array, which is the project's .ispac content. Internal interop helper, not exported
            from the module.

        .EXAMPLE
            $bytes = Export-SsisProjectObject -Project $project

            Returns the project's .ispac content as a byte array.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose .ispac bytes to retrieve, from Get-SsisProjectObject.

        .OUTPUTS
            System.Byte[]. The raw .ispac bytes of the project.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        return $Project.GetProjectBytes()
    }
}
