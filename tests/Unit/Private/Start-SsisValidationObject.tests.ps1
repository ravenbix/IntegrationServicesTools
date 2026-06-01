BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisValidationObject' {
    It 'Calls Validate with the 32-bit flag, SpecifyReference and the reference, and returns the id' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Use32 = $null; Usage = $null; Ref = $null }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Use32 = $use32
                $this.Usage = $usage
                $this.Ref = $reference
                return [long] 77
            }

            $result = Start-SsisValidationObject -Target $target -Reference 'theRef' -ReferenceUsage 'SpecifyReference' -Use32BitRuntime

            $result | Should -Be 77
            $target.Use32 | Should -BeTrue
            $target.Usage.ToString() | Should -Be 'SpecifyReference'
            $target.Ref | Should -Be 'theRef'
        }
    }

    It 'Passes UseNoReference and a null reference through' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Usage = $null; Ref = 'preset' }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Usage = $usage
                $this.Ref = $reference
                return [long] 1
            }

            $null = Start-SsisValidationObject -Target $target -Reference $null -ReferenceUsage 'UseNoReference'

            $target.Usage.ToString() | Should -Be 'UseNoReference'
            $target.Ref | Should -Be $null
        }
    }

    It 'Defaults the 32-bit flag to off (use32RuntimeOn64 = false) when not supplied' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Use32 = $null }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Use32 = $use32
                return [long] 1
            }

            $null = Start-SsisValidationObject -Target $target -Reference $null -ReferenceUsage 'UseAllReferences'

            $target.Use32 | Should -BeFalse
        }
    }
}
