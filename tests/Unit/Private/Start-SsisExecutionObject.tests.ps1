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

    It 'Passes an empty value-parameter set when neither logging nor parameters are given' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{ Use32 = $null }
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{}
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $this.Use32 = $use32
                $script:captured = $setValues
                return [long] 5
            }

            $result = Start-SsisExecutionObject -Package $package -Reference $null

            $result | Should -Be 5
            $package.Use32 | Should -BeFalse
            $script:captured.Count | Should -Be 0
        }
    }

    It 'Combines a logging-level set with parameter overrides' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{}
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{ 'PkgParam' = 'x' }
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $script:captured = $setValues
                return [long] 1
            }

            $splatStart = @{
                Package      = $package
                Reference    = $null
                Parameter    = @{ 'PkgParam' = 7 }
                LoggingLevel = 'Performance'
            }
            $null = Start-SsisExecutionObject @splatStart

            $script:captured.Count | Should -Be 2
            $logging = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'LOGGING_LEVEL' }
            $param = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'PkgParam' }
            $logging.ObjectType | Should -Be 50
            $logging.ParameterValue | Should -Be 2
            $param.ObjectType | Should -Be 30
            $param.ParameterValue | Should -Be 7
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
