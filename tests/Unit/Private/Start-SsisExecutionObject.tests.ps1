BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisExecutionObject' {
    It 'Calls Execute with the 32-bit flag and the reference, and returns the id' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{ Use32 = $null; Ref = $null; SetCount = $null }
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{}
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $this.Use32 = $use32
                $this.Ref = $reference
                $this.SetCount = $setValues.Count
                return [long] 99
            }

            $result = Start-SsisExecutionObject -Package $package -Reference 'theRef' -Use32BitRuntime

            $result | Should -Be 99
            $package.Use32 | Should -BeTrue
            $package.Ref | Should -Be 'theRef'
            $package.SetCount | Should -Be 0
        }
    }

    It 'Adds a logging-level value set (object type 50) when -LoggingLevel is given' {
        InModuleScope $script:moduleName {
            $captured = $null
            $package = [PSCustomObject]@{}
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{}
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $script:captured = $setValues
                return [long] 1
            }

            $null = Start-SsisExecutionObject -Package $package -Reference $null -LoggingLevel 'Verbose'

            $script:captured.Count | Should -Be 1
            $script:captured[0].ObjectType | Should -Be 50
            $script:captured[0].ParameterName | Should -Be 'LOGGING_LEVEL'
            $script:captured[0].ParameterValue | Should -Be 3
        }
    }

    It 'Resolves parameter scope: package parameter is object type 30, project parameter 20' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{}
            # Only 'PkgParam' is a package parameter; 'ProjParam' is not.
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{ 'PkgParam' = 'x' }
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $script:captured = $setValues
                return [long] 1
            }

            $null = Start-SsisExecutionObject -Package $package -Reference $null -Parameter @{ 'PkgParam' = 1; 'ProjParam' = 2 }

            $pkg = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'PkgParam' }
            $proj = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'ProjParam' }
            $pkg.ObjectType | Should -Be 30
            $proj.ObjectType | Should -Be 20
        }
    }
}
