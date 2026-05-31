# ------------------------------------------------------------------------------
#  IntegrationServicesTools - module load prefix
#
#  Loads the SQL Server Integration Services managed object model (MOM). The MOM
#  is not distributed on NuGet; the dbatools.library module is the only
#  redistributable source. Locate that module, load the MOM (plus SMO and
#  ConnectionInfo, whose types this module references directly), and register a
#  compiled assembly resolver so transitive dependencies load from the same folder.
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

# Register a COMPILED assembly resolver (NOT a PowerShell scriptblock). A scriptblock
# AssemblyResolve handler is unsafe here: the CLR invoking it spins up PowerShell
# machinery that can itself trigger assembly resolution, re-entering the handler until
# the stack overflows (observed when PSScriptAnalyzer runs while this module is
# imported). A compiled handler is invoked directly by the CLR with no PowerShell
# involvement, so it cannot recurse that way. Its static state also makes registration
# idempotent across Import-Module -Force within a single process.
if (-not ([System.Management.Automation.PSTypeName]'IntegrationServicesTools.AssemblyResolver').Type)
{
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;

namespace IntegrationServicesTools
{
    public static class AssemblyResolver
    {
        private static string _libraryFolder;
        private static bool _registered;

        public static void Register(string libraryFolder)
        {
            _libraryFolder = libraryFolder;

            if (!_registered)
            {
                AppDomain.CurrentDomain.AssemblyResolve += Resolve;
                _registered = true;
            }
        }

        private static Assembly Resolve(object sender, ResolveEventArgs args)
        {
            string requestedName = new AssemblyName(args.Name).Name;

            // Return an already-loaded assembly of the same simple name. This breaks
            // re-entrancy (an assembly mid-load is already in this list) and avoids
            // reloading assemblies other components have already loaded.
            foreach (Assembly loaded in AppDomain.CurrentDomain.GetAssemblies())
            {
                if (string.Equals(loaded.GetName().Name, requestedName, StringComparison.OrdinalIgnoreCase))
                {
                    return loaded;
                }
            }

            string candidate = Path.Combine(_libraryFolder, requestedName + ".dll");
            if (File.Exists(candidate))
            {
                return Assembly.LoadFrom(candidate);
            }

            return null;
        }
    }
}
'@
}

# Idempotent inside the compiled type: updates the folder, adds the handler only once.
[IntegrationServicesTools.AssemblyResolver]::Register($script:SsisLibFolder)

foreach ($assemblyName in @(
        'Microsoft.SqlServer.Management.IntegrationServices',
        'Microsoft.SqlServer.Smo',
        'Microsoft.SqlServer.ConnectionInfo'))
{
    $assemblyPath = Join-Path -Path $script:SsisLibFolder -ChildPath ($assemblyName + '.dll')
    $null = [System.Reflection.Assembly]::LoadFrom($assemblyPath)
}
