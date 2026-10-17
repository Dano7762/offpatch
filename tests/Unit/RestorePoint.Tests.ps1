# Point de restauration avant la première étape (cahier des charges 8.2) : jamais d'appel à Checkpoint-Computer sur une
# protection inactive, point créé ou existant constaté par Get-ComputerRestorePoint. Tout est simulé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpSystemProtection', 'New-OpRestorePoint') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    function Get-TestConfiguration([bool]$Enabled = $true) {
        [pscustomobject]@{ Settings = [pscustomobject]@{ client = [pscustomobject]@{ createRestorePointBeforeSession = $Enabled } } }
    }
    function Get-Point([string]$Description, [datetime]$When) {
        [pscustomobject]@{ Description = $Description; CreationTime = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($When) }
    }
}

Describe 'New-OpRestorePoint' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Checkpoint-Computer {}
    }

    It 'ne fait rien quand l''option est désactivée' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        $r = New-OpRestorePoint -Configuration (Get-TestConfiguration $false)
        $r.Status | Should -Be 'None'
        $r.Reason | Should -Match 'désactivée'
        Should -Invoke Checkpoint-Computer -Times 0 -Exactly
    }

    It 'n''appelle jamais Checkpoint-Computer sur une protection <Cas>' -TestCases @(
        @{ Cas = 'inactive'; Spp = $false; Storage = $false; Pattern = 'inactive' }
        @{ Cas = 'aux indicateurs en désaccord'; Spp = $true; Storage = $false; Pattern = 'désaccord' }
    ) {
        param($Cas, $Spp, $Storage, $Pattern)
        $script:p = [pscustomobject]@{ Active = $false; Spp = $Spp; Storage = $Storage }
        Mock Get-OpSystemProtection { $script:p }
        $r = New-OpRestorePoint -Configuration (Get-TestConfiguration)
        $r.Status | Should -Be 'None' -Because $Cas
        $r.Reason | Should -Match $Pattern
        Should -Invoke Checkpoint-Computer -Times 0 -Exactly
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' }
    }

    It 'crée le point et le constate dans la liste' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        Mock Get-ComputerRestorePoint { @((Get-Point 'ancien' (Get-Date).AddDays(-3)), (Get-Point 'OffPatch : avant les mises à jour' (Get-Date))) }
        $r = New-OpRestorePoint -Configuration (Get-TestConfiguration)
        $r.Status | Should -Be 'Created'
        $r.Description | Should -Be 'OffPatch : avant les mises à jour'
        $r.CreationTime | Should -BeOfType [datetime]
        $r.ProtectionEnabled | Should -BeFalse
        Should -Invoke Checkpoint-Computer -Times 1 -Exactly
    }

    It 'cite le point de moins de 24 heures quand Windows n''en crée pas de nouveau' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        Mock Get-ComputerRestorePoint { @(Get-Point 'Windows Update' (Get-Date).AddHours(-3)) }
        $r = New-OpRestorePoint -Configuration (Get-TestConfiguration)
        $r.Status | Should -Be 'Existing'
        $r.Description | Should -Be 'Windows Update'
    }

    It 'n''est jamais bloquant : échec de Checkpoint-Computer' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        Mock Checkpoint-Computer { throw 'service VSS arrêté' }
        $r = New-OpRestorePoint -Configuration (Get-TestConfiguration)
        $r.Status | Should -Be 'None'
        $r.Reason | Should -Match 'service VSS'
    }

    It 'respecte -WhatIf' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        New-OpRestorePoint -Configuration (Get-TestConfiguration) -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Checkpoint-Computer -Times 0 -Exactly
    }
}
