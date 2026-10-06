# Retrait de la marque « fichier téléchargé » des fichiers de l'outil (cahier des charges 8.1). Marque simulée par un
# flux Zone.Identifier écrit dans TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Unblock-OpToolFile') { . (Join-Path $root "app\module\OffPatch\Private\$name.ps1") }
    function Add-DownloadMark([string]$Path) {
        Set-Content -Path $Path -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3"
    }
}

Describe 'Unblock-OpToolFile' {
    BeforeEach {
        $tool = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        foreach ($d in 'app\module', 'config', 'depot\files') { New-Item -ItemType Directory -Force -Path (Join-Path $tool $d) | Out-Null }
        $files = @('Lancer-OffPatch.cmd', 'app\OffPatch.ps1', 'app\module\OffPatch.psm1', 'config\settings.json', 'depot\files\a.msu')
        foreach ($f in $files) { Set-Content -Path (Join-Path $tool $f) -Value 'x'; Add-DownloadMark (Join-Path $tool $f) }
    }

    It 'débloque le lanceur, app\ et config\, mais pas le dépôt' {
        Unblock-OpToolFile -Root $tool | Should -Be 4
        foreach ($f in 'Lancer-OffPatch.cmd', 'app\OffPatch.ps1', 'app\module\OffPatch.psm1', 'config\settings.json') {
            Get-Item -Path (Join-Path $tool $f) -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        Get-Item -Path (Join-Path $tool 'depot\files\a.msu') -Stream 'Zone.Identifier' | Should -Not -BeNullOrEmpty
    }

    It 'ne compte rien au second passage' {
        Unblock-OpToolFile -Root $tool | Out-Null
        Unblock-OpToolFile -Root $tool | Should -Be 0
    }

    It 'respecte -WhatIf' {
        Unblock-OpToolFile -Root $tool -WhatIf | Should -Be 0
        Get-Item -Path (Join-Path $tool 'app\OffPatch.ps1') -Stream 'Zone.Identifier' | Should -Not -BeNullOrEmpty
    }
}
