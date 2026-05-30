# ------------------------------------------------------------------------------
#  IntegrationServicesTools - module load prefix
#
#  Loads the SQL Server Integration Services managed object model (MOM). The MOM
#  is not distributed on NuGet; the dbatools.library module is the only
#  redistributable source. Locate that module, load the MOM (plus SMO and
#  ConnectionInfo, whose types this module references directly), and register an
#  assembly resolver so transitive dependencies load from the same folder.
# ------------------------------------------------------------------------------

$dbatoolsLibrary = Get-Module -Name 'dbatools.library' -ListAvailable |
    Sort-Object -Property 'Version' -Descending |
    Select-Object -First 1

if (-not $dbatoolsLibrary)
{
    throw "IntegrationServicesTools requires the 'dbatools.library' module (it ships the SSIS object model assemblies). Install it with: Install-Module -Name 'dbatools.library' -Scope CurrentUser"
}

$script:SsisLibFolder = Join-Path -Path $dbatoolsLibrary.ModuleBase -ChildPath 'desktop\lib'

if (-not (Test-Path -Path $script:SsisLibFolder))
{
    throw "IntegrationServicesTools could not locate the SSIS assemblies under '$($script:SsisLibFolder)'. The installed dbatools.library $($dbatoolsLibrary.Version) is not compatible."
}

$script:SsisAssemblyResolver = [System.ResolveEventHandler] {
    param ($sender, $eventArgs)

    $simpleName = ($eventArgs.Name -split ',')[0].Trim()
    $candidatePath = Join-Path -Path $script:SsisLibFolder -ChildPath ($simpleName + '.dll')

    if (Test-Path -Path $candidatePath)
    {
        return [System.Reflection.Assembly]::LoadFrom($candidatePath)
    }

    # Returning $null tells the CLR to continue to the next resolver.
    return $null
}

# Register once per process; Import-Module -Force re-runs this prefix each time.
if (-not $script:SsisAssemblyResolverRegistered)
{
    [System.AppDomain]::CurrentDomain.add_AssemblyResolve($script:SsisAssemblyResolver)
    $script:SsisAssemblyResolverRegistered = $true
}

foreach ($assemblyName in @(
        'Microsoft.SqlServer.Management.IntegrationServices',
        'Microsoft.SqlServer.Smo',
        'Microsoft.SqlServer.ConnectionInfo'))
{
    $assemblyPath = Join-Path -Path $script:SsisLibFolder -ChildPath ($assemblyName + '.dll')
    $null = [System.Reflection.Assembly]::LoadFrom($assemblyPath)
}
