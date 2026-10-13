# Planificateur (cahier des charges 8.3) : ordre, prérequis bloquants, UBR projeté, points de redémarrage. États de
# détection et manifeste simulés ; rien n'est lu sur le PC réel.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }

    $tool = Join-Path $TestDrive 'outil'
    New-Item -ItemType Directory -Force -Path $tool | Out-Null
    Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool

    # Élément du manifeste et son état de détection.
    function ConvertTo-TestStep([string]$Id, [string]$Category, [int]$Order, [string]$State = 'Pending', [hashtable]$Fields) {
        $item = [ordered]@{ id = $Id; category = $Category; order = $Order; requiresReboot = $false; prerequisites = @(); runsAfter = @() }
        if ($Fields) { foreach ($k in $Fields.Keys) { $item[$k] = $Fields[$k] } }
        [pscustomobject]@{
            Item  = [pscustomobject]$item
            State = [pscustomobject]@{ Id = $Id; Category = $Category; State = $State; Reason = "détection $State"; Installed = $null; Available = $null }
        }
    }
    function Get-TestPlan([object[]]$Steps, [int]$Ubr = 9457, [object[]]$ExtraStates = @()) {
        $script:testItems = @($Steps | ForEach-Object { $_.Item })
        Mock Read-OpManifest { [pscustomobject]@{ schemaVersion = 1; generatedAt = '2026-10-14T00:00:00Z'; items = $script:testItems } }
        $info = [pscustomobject]@{ Target = 'win11-x64'; CurrentBuild = 26200; Ubr = $Ubr; Office = $null }
        @(Get-OpInstallPlan -Root $tool -SystemInfo $info -UpdateState (@($Steps | ForEach-Object { $_.State }) + $ExtraStates))
    }
    function Join-TestField([hashtable]$Base, [hashtable]$Extra) { $c = $Base.Clone(); foreach ($k in $Extra.Keys) { $c[$k] = $Extra[$k] }; $c }
    function Get-StepOf([object[]]$Plan, [string]$Id) { $Plan | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

    $cp = @{ requiresReboot = $true; resultingUbr = 1742 }
    $lcu = @{ requiresReboot = $true; resultingUbr = 9550; prerequisites = @('windows-checkpoint') }
    $ekb = @{ requiresReboot = $true; minUbr = 9550; resultingBuild = 26300; runsAfter = @('windows-lcu') }
}

Describe 'Get-OpInstallPlan : ordre' {
    It 'suit l''ordre par défaut quel que soit l''ordre de détection' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'office' 'office-source' 50
            ConvertTo-TestStep 'net' 'dotnet' 40
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 'UpToDate' $cp
            ConvertTo-TestStep 'def' 'defender' 11 -Fields @{ runsAfter = @('defender-platform') }
            ConvertTo-TestStep 'plat' 'defender-platform' 10
        )
        $plan.Id | Should -Be @('plat', 'def', 'cp', 'lcu', 'ekb', 'net', 'office')
        $plan.Sequence | Should -Be @(1, 2, 3, 4, 5, 6, 7)
        (Get-StepOf $plan 'lcu').Prerequisites | Should -Be @('cp')
        (Get-StepOf $plan 'ekb').RunsAfter | Should -Be @('lcu')
    }

    It 'place une étape après sa dépendance d''ordre même si son order est plus petit' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'a' 'dotnet' 5 -Fields @{ runsAfter = @('b') }
            ConvertTo-TestStep 'b' 'defender' 11
        )
        $plan.Id | Should -Be @('b', 'a')
    }

    It 'garde en fin de plan les lignes sans élément (catégorie absente du dépôt)' {
        $plan = Get-TestPlan @(ConvertTo-TestStep 'net' 'dotnet' 40) -ExtraStates @([pscustomobject]@{ Id = $null; Category = 'windows-lcu'; State = 'MissingFromDepot'; Reason = 'absent'; Installed = $null; Available = $null })
        $plan.Category | Should -Be @('dotnet', 'windows-lcu')
        $plan[1].State | Should -Be 'MissingFromDepot'
    }
}

Describe 'Get-OpInstallPlan : prérequis et UBR projeté' {
    It 'enablement package prévu quand la cumulative prévue atteint minUbr (25H2 .9457 avec cumulative .9550)' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 'UpToDate' $cp
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
        )
        (Get-StepOf $plan 'lcu').State | Should -Be 'Pending'
        (Get-StepOf $plan 'ekb').State | Should -Be 'Pending'
    }

    It 'enablement package ignoré quand aucune cumulative prévue n''atteint minUbr (P6)' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 'UpToDate' (Join-TestField $lcu @{ resultingUbr = 9457 })
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
        )
        (Get-StepOf $plan 'ekb').State | Should -Be 'SkippedPrerequisite'
        (Get-StepOf $plan 'ekb').Reason | Should -Match '9457.*9550'
    }

    It 'checkpoint en erreur : cumulative ignorée, et l''enablement package faute d''UBR projeté' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 'Error' $cp
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
            ConvertTo-TestStep 'net' 'dotnet' 40
        )
        (Get-StepOf $plan 'lcu').State | Should -Be 'SkippedPrerequisite'
        (Get-StepOf $plan 'lcu').Reason | Should -Match 'cp : Error'
        (Get-StepOf $plan 'ekb').State | Should -Be 'SkippedPrerequisite'
        (Get-StepOf $plan 'net').State | Should -Be 'Pending'
    }

    It 'prérequis à installer plus tôt dans le plan : rempli' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 -Fields $cp
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu
        ) -Ubr 1000
        (Get-StepOf $plan 'cp').State | Should -Be 'Pending'
        (Get-StepOf $plan 'lcu').State | Should -Be 'Pending'
    }

    It 'SSU Windows 10 absent du dépôt : cumulative ignorée ; SSU non applicable : prérequis rempli' {
        $w10lcu = @{ requiresReboot = $true; resultingUbr = 6456; prerequisites = @('windows-ssu') }
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'ssu' 'windows-ssu' 18 'MissingFromDepot'
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $w10lcu
        )
        (Get-StepOf $plan 'lcu').State | Should -Be 'SkippedPrerequisite'
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'ssu' 'windows-ssu' 18 'NotApplicable'
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $w10lcu
        )
        (Get-StepOf $plan 'lcu').State | Should -Be 'Pending'
    }

    It 'catégorie de prérequis sans élément : rien à attendre ; identifiant inconnu : ignorée' {
        $plan = Get-TestPlan @(ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu)
        (Get-StepOf $plan 'lcu').State | Should -Be 'Pending'
        $plan = Get-TestPlan @(ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields (Join-TestField $lcu @{ prerequisites = @('win11-x64-checkpoint-inconnue') }))
        (Get-StepOf $plan 'lcu').State | Should -Be 'SkippedPrerequisite'
        (Get-StepOf $plan 'lcu').Reason | Should -Match 'absent du dépôt'
    }

    It 'plateforme Defender en erreur : définitions prévues quand même (dépendance d''ordre)' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'plat' 'defender-platform' 10 'Error'
            ConvertTo-TestStep 'def' 'defender' 11 -Fields @{ runsAfter = @('defender-platform') }
        )
        (Get-StepOf $plan 'def').State | Should -Be 'Pending'
    }
}

Describe 'Get-OpInstallPlan : points de redémarrage' {
    It 'checkpoint et cumulative : un seul redémarrage, après la cumulative ; puis un après l''enablement package' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'plat' 'defender-platform' 10
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 -Fields $cp
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 -Fields $lcu
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
            ConvertTo-TestStep 'net' 'dotnet' 40
        ) -Ubr 1000
        ($plan | Where-Object RebootAfter).Id | Should -Be @('lcu', 'ekb')
    }

    It 'checkpoint seule à installer : redémarrage après elle' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'cp' 'windows-checkpoint' 19 -Fields $cp
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 'MissingFromDepot' $lcu
            ConvertTo-TestStep 'net' 'dotnet' 40
        ) -Ubr 1000
        ($plan | Where-Object RebootAfter).Id | Should -Be @('cp')
    }

    It 'aucun redémarrage pour une étape ignorée ou à jour' {
        $plan = Get-TestPlan @(
            ConvertTo-TestStep 'lcu' 'windows-lcu' 20 'UpToDate' $lcu
            ConvertTo-TestStep 'ekb' 'windows-ekb' 30 -Fields $ekb
        ) -Ubr 9000
        @($plan | Where-Object RebootAfter).Count | Should -Be 0
    }
}
