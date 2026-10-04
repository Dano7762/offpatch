# Distinction Windows 10 / Windows 11 sur registre simulé (R-09). Aucun accès au registre réel.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Get-OpWindowsIdentity.ps1')
}

Describe 'Get-OpWindowsIdentity' {
    Context 'Windows 11 25H2 dont ProductName indique « Windows 10 Pro »' {
        BeforeAll {
            Mock Get-ItemProperty {
                [pscustomobject]@{ ProductName = 'Windows 10 Pro'; CurrentBuild = '26200'; UBR = 9457; DisplayVersion = '25H2'; EditionID = 'Professional' }
            }
            Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Professionnel' } }
            $identity = Get-OpWindowsIdentity
        }

        It 'classe le système en Windows 11 d''après CurrentBuild' {
            $identity.Family | Should -Be 'Windows11'
        }

        It 'relève la build et l''UBR' {
            $identity.CurrentBuild | Should -Be 26200
            $identity.Ubr | Should -Be 9457
        }

        It 'prend le libellé dans Win32_OperatingSystem.Caption, pas dans ProductName' {
            $identity.Caption | Should -Be 'Microsoft Windows 11 Professionnel'
        }
    }

    Context 'Windows 10 22H2' {
        It 'classe le système en Windows 10' {
            Mock Get-ItemProperty {
                [pscustomobject]@{ ProductName = 'Windows 10 Pro'; CurrentBuild = '19045'; UBR = 7727; DisplayVersion = '22H2'; EditionID = 'Professional' }
            }
            Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Professionnel' } }
            (Get-OpWindowsIdentity).Family | Should -Be 'Windows10'
        }
    }

    Context 'Limite à la build 22000' {
        It 'classe la build 22000 en Windows 11' {
            Mock Get-ItemProperty { [pscustomobject]@{ ProductName = 'Windows 10 Pro'; CurrentBuild = '22000'; UBR = 1; EditionID = 'Professional' } }
            Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Professionnel' } }
            (Get-OpWindowsIdentity).Family | Should -Be 'Windows11'
        }
    }
}
