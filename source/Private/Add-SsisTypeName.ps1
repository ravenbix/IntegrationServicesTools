function Add-SsisTypeName
{
    <#
        .SYNOPSIS
            Inserts a custom PSTypeName onto an object so module format views apply to it.

        .DESCRIPTION
            Decorates the input object by inserting the given type name at the front of its
            PSTypeNames list, then returns the object. Used to tag returned MOM objects (for example
            'Ssis.Catalog') so the module's format.ps1xml controls their display. Internal helper,
            not exported from the module.

        .EXAMPLE
            $catalog | Add-SsisTypeName -TypeName 'Ssis.Catalog'

            Tags the catalog object with the Ssis.Catalog type name and returns it.

        .PARAMETER InputObject
            The object to decorate. It is passed through unchanged apart from the inserted type name.
            A null value is passed through without modification.

        .PARAMETER TypeName
            The PSTypeName to insert at the front of the object's type list, for example
            'Ssis.Catalog' or 'Ssis.Folder'.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $TypeName
    )

    process
    {
        if ($null -ne $InputObject)
        {
            $InputObject.PSObject.TypeNames.Insert(0, $TypeName)
        }

        $InputObject
    }
}
