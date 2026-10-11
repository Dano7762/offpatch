# Purge du dépôt (cahier des charges 7.3) : rétention par cible des cumulatives Windows et .NET, dernière version
# Defender, éléments épinglés jamais retirés, comptage de références des fichiers partagés, orphelins listés puis
# supprimés seulement sur demande. Dépôt fabriqué dans TestDrive, aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($name in 'Get-OpDepotPurgePlan', 'Write-OpLog', 'ConvertTo-OpMaskedText', 'Get-OpConfiguration', 'Read-OpJsonFile', 'Test-OpConfiguration',
        'Get-OpPath', 'Get-OpRoot', 'Read-OpManifest', 'Test-OpManifest', 'Save-OpManifest') {
        . (Join-Path $module "Private\$name.ps1")
    }
    . (Join-Path $module 'Public\Invoke-OpDepotPurge.ps1')

    $configuration = [pscustomobject]@{
        Settings    = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        PinnedItems = Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $pinnedId = $configuration.PinnedItems.items[0].id

    function Get-Sha([string]$Name) { ('{0:x8}' -f [Math]::Abs($Name.GetHashCode())).PadLeft(64, '0') }
    function Get-Item2([string]$Id, [string]$Target, [string]$Category, [string[]]$Names, [hashtable]$Extra = @{}) {
        $os, $arch = $Target -split '-', 2
        $item = [ordered]@{ id = $Id; category = $Category; target = [pscustomobject]@{ os = $os; arch = $arch }; order = 20; requiresReboot = $false
            files = @(foreach ($n in $Names) { [pscustomobject]@{ path = "files/$(Get-Sha $n)/$n"; sha256 = (Get-Sha $n); size = [long]100 } })
        }
        foreach ($k in $Extra.Keys) { $item[$k] = $Extra[$k] }
        [pscustomobject]$item
    }
    function Get-Lcu([string]$Target, [string]$Kb, [string]$Date, [int]$Ubr, [string[]]$Names) {
        Get-Item2 "$Target-lcu-$Kb" $Target 'windows-lcu' $Names @{ kb = $Kb; releaseDate = $Date; baseBuilds = @(26100); resultingUbr = $Ubr }
    }
    function Get-IdList($Items) { @($Items | ForEach-Object { $_.id }) }
}

Describe 'Get-OpDepotPurgePlan' {
    It 'garde par cible les cumulatives les plus récentes, selon retention.windowsMonths' {
        $manifest = [pscustomobject]@{ schemaVersion = 1; items = @(
                Get-Lcu 'win11-x64' 'KB3' '2026-10-13' 9600 @('c.msu')
                Get-Lcu 'win11-x64' 'KB1' '2026-08-11' 9300 @('a.msu')
                Get-Lcu 'win11-x64' 'KB2' '2026-09-08' 9457 @('b.msu')
                Get-Lcu 'win10-x64' 'KB11' '2026-08-11' 7600 @('w1.msu')
                Get-Lcu 'win10-x64' 'KB12' '2026-09-08' 7727 @('w2.msu')
                Get-Lcu 'win10-x64' 'KB13' '2026-10-13' 7800 @('w3.msu')
            ) }
        $p = Get-OpDepotPurgePlan -Manifest $manifest -Configuration $configuration
        Get-IdList $p.Removed | Sort-Object | Should -Be @('win10-x64-lcu-KB11', 'win11-x64-lcu-KB1', 'win11-x64-lcu-KB2')
        @($p.RemovedFiles | ForEach-Object { ($_.Path -split '/')[-1] }) | Sort-Object | Should -Be @('a.msu', 'b.msu', 'w1.msu')
    }

    It 'garde la version Defender la plus élevée (comparaison de versions, pas de texte)' {
        $manifest = [pscustomobject]@{ schemaVersion = 1; items = @(
                Get-Item2 'win11-x64-defender-1.459.90.0' 'win11-x64' 'defender' @('mpam-fe-ancien.exe') @{ version = '1.459.90.0' }
                Get-Item2 'win11-x64-defender-1.459.675.0' 'win11-x64' 'defender' @('mpam-fe.exe') @{ version = '1.459.675.0' }
                Get-Item2 'win11-x64-defender-platform-4.18.26080.4' 'win11-x64' 'defender-platform' @('p2.exe') @{ version = '4.18.26080.4' }
                Get-Item2 'win11-x64-defender-platform-4.18.25080.5' 'win11-x64' 'defender-platform' @('p1.exe') @{ version = '4.18.25080.5' }
            ) }
        Get-IdList (Get-OpDepotPurgePlan -Manifest $manifest -Configuration $configuration).Removed | Sort-Object |
            Should -Be @('win11-x64-defender-1.459.90.0', 'win11-x64-defender-platform-4.18.25080.5')
    }

    It 'ne retire jamais un élément épinglé ni une checkpoint, et garde un fichier encore référencé' {
        $manifest = [pscustomobject]@{ schemaVersion = 1; items = @(
                Get-Item2 $pinnedId 'win11-x64' 'windows-ekb' @('ekb.msu')
                Get-Item2 'win11-x64-checkpoint-KB9' 'win11-x64' 'windows-checkpoint' @('cp.msu')
                Get-Lcu 'win11-x64' 'KB1' '2026-08-11' 9300 @('a.msu', 'partage.msu')
                Get-Lcu 'win11-x64' 'KB2' '2026-09-08' 9457 @('b.msu', 'partage.msu')
            ) }
        $p = Get-OpDepotPurgePlan -Manifest $manifest -Configuration $configuration
        Get-IdList $p.Removed | Should -Be @('win11-x64-lcu-KB1')
        Get-IdList $p.Kept | Should -Contain $pinnedId
        Get-IdList $p.Kept | Should -Contain 'win11-x64-checkpoint-KB9'
        @($p.RemovedFiles | ForEach-Object { ($_.Path -split '/')[-1] }) | Should -Be @('a.msu')
    }

    It 'ne retire rien d''une cible sans valeur de rétention' {
        $manifest = [pscustomobject]@{ schemaVersion = 1; items = @(
                Get-Lcu 'win10-arm64' 'KB1' '2026-08-11' 1 @('a.msu')
                Get-Lcu 'win10-arm64' 'KB2' '2026-09-08' 2 @('b.msu')
            ) }
        @((Get-OpDepotPurgePlan -Manifest $manifest -Configuration $configuration).Removed).Count | Should -Be 0
    }
}

Describe 'Invoke-OpDepotPurge' {
    BeforeAll {
        Mock Write-OpLog {}
        # Outil copié dans TestDrive : dépôt avec deux mois de cumulative win11-x64 (rétention 1), une checkpoint
        # partagée, un orphelin dans files/, un fichier en cours dans .tmp/ et une source Office.
        function Initialize-TestDepot([string]$Name) {
            $tool = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Force -Path $tool | Out-Null
            Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
            Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
            $items = @(
                Get-Lcu 'win11-x64' 'KB1' '2026-08-11' 9300 @('a.msu', 'cp.msu')
                Get-Lcu 'win11-x64' 'KB2' '2026-09-08' 9457 @('b.msu', 'cp.msu')
            )
            $depot = Join-Path $tool 'depot'
            foreach ($i in $items) { foreach ($f in $i.files) { $p = Join-Path $depot $f.path; New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [IO.File]::WriteAllBytes($p, (New-Object byte[] 100)) } }
            $orphan = Join-Path $depot "files/$(Get-Sha 'orphelin.msu')/orphelin.msu"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $orphan) | Out-Null
            [IO.File]::WriteAllText($orphan, 'x')
            New-Item -ItemType Directory -Force -Path (Join-Path $depot '.tmp\abc'), (Join-Path $depot 'office\current') | Out-Null
            [IO.File]::WriteAllText((Join-Path $depot '.tmp\abc\en-cours.msu'), 'x')
            [IO.File]::WriteAllText((Join-Path $depot 'office\current\v64.cab'), 'x')
            Save-OpManifest -Manifest ([pscustomobject]@{ schemaVersion = 1; toolVersion = $null; items = $items }) -Path (Join-Path $depot 'manifest.json')
            $tool
        }
    }

    It 'réécrit le manifeste, supprime les fichiers sans référence et leur dossier, liste l''orphelin sans le supprimer' {
        $tool = Initialize-TestDepot 'p1'
        $r = Invoke-OpDepotPurge -Root $tool
        $r.RemovedItems | Should -Be @('win11-x64-lcu-KB1')
        $r.RemovedFiles | Should -Be @("files/$(Get-Sha 'a.msu')/a.msu")
        $r.FreedBytes | Should -Be 100
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'a.msu')") | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'cp.msu')\cp.msu") | Should -BeTrue
        Get-IdList (Read-OpManifest -Path (Join-Path $tool 'depot\manifest.json')).items | Should -Be @('win11-x64-lcu-KB2')
        @($r.Orphans | ForEach-Object { $_.Path }) | Should -Be @("files/$(Get-Sha 'orphelin.msu')/orphelin.msu")
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'orphelin.msu')\orphelin.msu") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $tool 'depot\.tmp\abc\en-cours.msu') | Should -BeTrue
    }

    It 'supprime les orphelins avec -RemoveOrphans -Force, jamais .tmp ni office' {
        $tool = Initialize-TestDepot 'p2'
        $r = Invoke-OpDepotPurge -Root $tool -RemoveOrphans -Force
        $r.RemovedOrphans | Should -Be @("files/$(Get-Sha 'orphelin.msu')/orphelin.msu")
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'orphelin.msu')") | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $tool 'depot\.tmp\abc\en-cours.msu') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $tool 'depot\office\current\v64.cab') | Should -BeTrue
    }

    It 'respecte -WhatIf : manifeste et fichiers inchangés' {
        $tool = Initialize-TestDepot 'p3'
        $r = Invoke-OpDepotPurge -Root $tool -RemoveOrphans -Force -WhatIf
        @($r.RemovedItems).Count | Should -Be 0
        @((Read-OpManifest -Path (Join-Path $tool 'depot\manifest.json')).items).Count | Should -Be 2
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'a.msu')\a.msu") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$(Get-Sha 'orphelin.msu')\orphelin.msu") | Should -BeTrue
    }

    It 'ne fait rien sur un dépôt neuf' {
        $tool = Join-Path $TestDrive 'p4'
        New-Item -ItemType Directory -Force -Path $tool | Out-Null
        Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
        $r = Invoke-OpDepotPurge -Root $tool
        @($r.RemovedItems).Count + @($r.Orphans).Count | Should -Be 0
    }
}
