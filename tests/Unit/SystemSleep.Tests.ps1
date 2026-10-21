# Mise en veille suspendue pendant les installations (cahier des charges 8.6). SetThreadExecutionState réel : demande
# portée par le thread du test, levée à la fin, aucun réglage d'alimentation modifié.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Suspend-OpSystemSleep', 'Resume-OpSystemSleep') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
}

Describe 'Suspend-OpSystemSleep et Resume-OpSystemSleep' {
    BeforeEach { Mock Write-OpLog {} }

    It 'pose la demande ES_SYSTEM_REQUIRED et rend l''état d''avant, appels imbriqués compris' {
        $outer = Suspend-OpSystemSleep -Confirm:$false
        $outer | Should -Not -BeNullOrEmpty
        $inner = Suspend-OpSystemSleep -Confirm:$false
        ($inner -band 1) | Should -Be 1 -Because 'la demande extérieure est active'
        Resume-OpSystemSleep -PreviousState $inner -Confirm:$false
        $check = Suspend-OpSystemSleep -Confirm:$false
        ($check -band 1) | Should -Be 1 -Because 'l''appel intérieur ne lève pas la demande extérieure'
        Resume-OpSystemSleep -PreviousState $check -Confirm:$false
        Resume-OpSystemSleep -PreviousState $outer -Confirm:$false
        $after = Suspend-OpSystemSleep -Confirm:$false
        $after | Should -Be $outer
        Resume-OpSystemSleep -PreviousState $after -Confirm:$false
    }

    It 'ne fait rien avec -WhatIf ou sans état précédent' {
        Suspend-OpSystemSleep -WhatIf | Should -BeNullOrEmpty
        { Resume-OpSystemSleep -PreviousState $null -Confirm:$false } | Should -Not -Throw
    }
}
