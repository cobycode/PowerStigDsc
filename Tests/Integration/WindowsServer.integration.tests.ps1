$script:DSCModuleName            = 'PowerStigDsc'
$script:DSCCompositeResourceName = 'WindowsServer'

#region HEADER
# Integration Test Template Version: 1.1.1
[String] $script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ( (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
     (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $script:moduleRoot -ChildPath '\DSCResource.Tests\'))
}

Import-Module (Join-Path -Path $script:moduleRoot -ChildPath 'Tests\helper.psm1' ) -Force
Import-Module (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1') -Force
$TestEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:DSCModuleName `
    -DSCResourceName $script:DSCCompositeResourceName `
    -TestType Integration
#endregion

# Using try/finally to always cleanup even if something awful happens.
try
{
    #region Integration Tests
    $ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:DSCCompositeResourceName).config.ps1"
    . $ConfigFile

    $stigList = Get-StigVersionTable -CompositeResourceName $script:DSCCompositeResourceName

    #region Integration Tests
    Foreach ($stig in $stigList)
    {
        [xml] $dscXml = Get-Content -Path $stig.Path

        Describe "Windows $($stig.TechnologyVersion) $($stig.TechnologyRole) $($stig.StigVersion) mof output" {

            It 'Should compile the MOF without throwing' {
                {
                    & "$($script:DSCCompositeResourceName)_config" `
                        -OsVersion $stig.TechnologyVersion  `
                        -OsRole $stig.TechnologyRole `
                        -StigVersion $stig.StigVersion `
                        -ForestName 'integration.test' `
                        -DomainName 'integration.test' `
                        -OutputPath $TestDrive
                } | Should not throw
            }

            $ConfigurationDocumentPath = "$TestDrive\localhost.mof"

            $instances = [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($ConfigurationDocumentPath, 4)

            Context 'AuditPolicy' {
                $hasAllSettings = $true
                $dscXml         = $dscXml.DISASTIG.AuditPolicyRule.Rule
                $dscMof         = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[AuditPolicySubcategory\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing Audit Policy Setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) Audit Policy settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'Permissions' {
                $hasAllSettings = $true
                <#
                    https://github.com/Microsoft/PowerStigDsc/issues/1
                    Once the Composite is updated to configure ActiveDirectoryAuditRuleEntry,
                    remove '-and $PSItem.dscResource -ne "ActiveDirectoryAuditRuleEntry"' from the
                    following where cmdlet
                #>
                $dscXmlPermissionPolicy = $dscXml.DISASTIG.PermissionRule.Rule |
                    Where-Object { $PSItem.conversionstatus -eq "pass" -and
                                   $PSItem.dscResource -ne "ActiveDirectoryAuditRuleEntry"}
                $dscMofPermissionPolicy = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[NTFSAccessEntry\]|\[RegistryAccessEntry\]"}

                Foreach ($setting in $dscXmlPermissionPolicy)
                {
                    If (-not ($dscMofPermissionPolicy.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing permission setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXmlPermissionPolicy.Count) permission settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'Registry' {
                $hasAllSettings = $true
                $dscXml   = $dscXml.DISASTIG.RegistryRule.Rule
                $dscMof   = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[Registry\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing registry Setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) Registry settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'WMI' {
                $hasAllSettings = $true
                $dscXml    = $dscXml.DISASTIG.WmiRule.Rule
                $dscMof   = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[script\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing wmi setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) wmi settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'Services' {
                $hasAllSettings = $true
                $dscXml = $dscXml.DISASTIG.ServiceRule.Rule
                $dscMof = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[xService\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing service setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) service settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'AccountPolicy' {
                $hasAllSettings = $true
                $dscXml = $dscXml.DISASTIG.AccountPolicyRule.Rule
                $dscMof = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[AccountPolicy\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing security setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) security settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'UserRightsAssignment' {
                $hasAllSettings = $true
                $dscXml = $dscXml.DISASTIG.UserRightRule.Rule
                $dscMof = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[UserRightsAssignment\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing user right $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) user rights settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'SecurityOption' {
                $hasAllSettings = $true
                $dscXml = $dscXml.DISASTIG.SecurityOptionRule.Rule
                $dscMof = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[SecurityOption\]"}

                Foreach ( $setting in $dscXml )
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing security setting $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) security settings" {
                    $hasAllSettings | Should Be $true
                }
            }

            Context 'Windows Feature' {
                $hasAllSettings = $true
                $dscXml = $dscXml.DISASTIG.WindowsFeatureRule.Rule
                $dscMof = $instances |
                    Where-Object {$PSItem.ResourceID -match "\[WindowsFeature\]"}

                Foreach ($setting in $dscXml)
                {
                    If (-not ($dscMof.ResourceID -match $setting.Id) )
                    {
                        Write-Warning -Message "Missing windows feature $($setting.Id)"
                        $hasAllSettings = $false
                    }
                }

                It "Should have $($dscXml.Count) windows feature settings" {
                    $hasAllSettings | Should Be $true
                }
            }
        }

        Describe "Windows $($stig.TechnologyVersion) $($stig.TechnologyRole) $($stig.StigVersion) Single SkipRule/RuleType mof output" {

            $skipRule     = Get-Random -InputObject $dscXml.DISASTIG.RegistryRule.Rule.id
            $skipRuleType = "AuditPolicyRule"

            It 'Should compile the MOF without throwing' {
                {
                    & "$($script:DSCCompositeResourceName)_config" `
                        -OsVersion $stig.TechnologyVersion  `
                        -OsRole $stig.TechnologyRole `
                        -StigVersion $stig.StigVersion `
                        -ForestName 'integration.test' `
                        -DomainName 'integration.test' `
                        -SkipRule $skipRule `
                        -SkipRuleType $skipRuleType `
                        -OutputPath $TestDrive
                } | Should not throw
            }

            #region Gets the mof content
            $ConfigurationDocumentPath = "$TestDrive\localhost.mof"
            $instances = [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($ConfigurationDocumentPath, 4)
            #endregion

            Context 'Skip check' {

                #region counts how many Skips there are and how many there should be.
                $dscXml = $dscXml.DISASTIG.AuditPolicyRule.Rule | Where-Object {$_.ConversionStatus -eq "pass"}
                $dscXml = ($($dscXml.Count) + $($SkipRule.Count))

                $dscMof = $instances | Where-Object {$PSItem.ResourceID -match "\[Skip\]"}
                #endregion

                It "Should have $dscXml Skipped settings" {
                    $dscMof.count | Should Be $dscXml
                }
            }
        }

        Describe "Windows $($stig.TechnologyVersion) $($stig.TechnologyRole) $($stig.StigVersion) Multiple SkipRule/RuleType mof output" {

            $skipRule     = Get-Random -InputObject $dscXml.DISASTIG.RegistryRule.Rule.id -Count 2
            $skipRuleType = @('AuditPolicyRule','AccountPolicyRule')

            It 'Should compile the MOF without throwing' {
                {
                    & "$($script:DSCCompositeResourceName)_config" `
                        -OsVersion $stig.TechnologyVersion  `
                        -OsRole $stig.TechnologyRole `
                        -StigVersion $stig.StigVersion `
                        -ForestName 'integration.test' `
                        -DomainName 'integration.test' `
                        -SkipRule $skipRule `
                        -SkipRuleType $skipRuleType `
                        -OutputPath $TestDrive
                } | Should not throw
            }

            #region Gets the mof content
            $ConfigurationDocumentPath = "$TestDrive\localhost.mof"
            $instances = [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($ConfigurationDocumentPath, 4)
            #endregion

            Context 'Skip check' {

                #region counts how many Skips there are and how many there should be.
                $dscAuditXml = $dscXml.DISASTIG.AuditPolicyRule.Rule | Where-Object {$_.ConversionStatus -eq "Pass"}
                $dscPermissionXml = $dscXml.DISASTIG.AccountPolicyRule.Rule | Where-Object {$_.ConversionStatus -eq "Pass"}

                $dscXml = ($($dscAuditXml.Count) + $($dscPermissionXml.count) + $($skipRule.Count))

                $dscMof = $instances | Where-Object {$PSItem.ResourceID -match "\[Skip\]"}
                #endregion

                It "Should have $dscXml Skipped settings" {
                    $dscMof.count | Should Be $dscXml
                }
            }
        }
    }
    #endregion Tests
}
finally
{
    #region FOOTER
    Restore-TestEnvironment -TestEnvironment $TestEnvironment
    #endregion
}
