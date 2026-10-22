# Copie sur un support (cahier des charges 7.4, étapes 4 à 6) avec le vrai robocopy, d'un outil factice vers un support
# factice, tous deux dans TestDrive. Volume du support simulé (sinon refusé : même lecteur que l'outil), manifeste lu et
# écrit par des simulacres (éléments réduits aux champs utiles). Rien n'est copié hors de TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fonctions factices du module : leurs paramètres servent aux filtres des simulacres.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Read-OpManifest', 'Save-OpManifest', 'Format-OpSize', 'Get-OpVolumeInfo', 'Invoke-OpProcess', 'Assert-OpNotCancelled', 'Write-OpLog', 'Write-OpProgress', 'ConvertTo-OpMaskedText') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    foreach ($name in 'Get-OpSupportPlan', 'Copy-OpSupportReport', 'Copy-OpSupport') { . (Join-Path $repo "app\module\OffPatch\Public\$name.ps1") }
    . (Join-Path $repo 'app\gui\Dialogs\PrepareSupport.ps1')
    function Get-OpDepotSelection { param($Root) }

    function Write-TestFile([string]$Path, [int]$Size = 1) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [IO.File]::WriteAllBytes($Path, (New-Object byte[] $Size))
    }
    # Outil : racine, app, config, tools, rapports ; dépôt : deux cibles (une partage le fichier Defender), Office.
    function Initialize-TestTool([string]$Path) {
        foreach ($f in 'Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE', 'app\OffPatch.ps1', 'app\gui\x.xaml', 'config\settings.json', 'tools\odt\.gitkeep', 'logs\l.log') { Write-TestFile (Join-Path $Path $f) }
        Write-TestFile (Join-Path $Path 'depot\files\aa\lcu.msu') 1000
        Write-TestFile (Join-Path $Path 'depot\files\bb\def.exe') 100
        Write-TestFile (Join-Path $Path 'depot\files\cc\lcu10.msu') 500
        Write-TestFile (Join-Path $Path 'depot\office\current\Office\Data\v64.cab') 50
        $items = @(
            '{ "id": "win11-x64-lcu", "category": "windows-lcu", "target": { "os": "win11", "arch": "x64" }, "files": [ { "path": "files/aa/lcu.msu", "sha256": "a", "size": 1000 } ] }'
            '{ "id": "win11-x64-defender", "category": "defender", "target": { "os": "win11", "arch": "x64" }, "files": [ { "path": "files/bb/def.exe", "sha256": "b", "size": 100 } ] }'
            '{ "id": "win10-x64-lcu", "category": "windows-lcu", "target": { "os": "win10", "arch": "x64" }, "files": [ { "path": "files/cc/lcu10.msu", "sha256": "c", "size": 500 } ] }'
            '{ "id": "office-current-16.0.1.1", "category": "office-source", "channel": "Current", "folder": "office/current", "files": [ { "path": "office/current/Office/Data/v64.cab", "sha256": "d", "size": 50 } ] }')
        [IO.File]::WriteAllText((Join-Path $Path 'depot\manifest.json'), ('{ "schemaVersion": 1, "generatedAt": "2026-10-18T07:40:58Z", "toolVersion": "0.6.0", "items": [ ' + ($items -join ', ') + ' ] }'))
    }
    Mock Read-OpManifest { [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    Mock Write-OpLog {}
}

Describe 'Copy-OpSupport' {
    BeforeEach {
        $script:tool = Join-Path $TestDrive ('outil-' + [guid]::NewGuid().ToString('N'))
        $script:support = Join-Path $TestDrive ('support-' + [guid]::NewGuid().ToString('N'))
        Initialize-TestTool $script:tool
        New-Item -ItemType Directory -Force -Path $script:support | Out-Null
        Mock Get-OpVolumeInfo { [pscustomobject]@{ Root = 'S:\'; IsReady = $true; FileSystem = 'exFAT'; FreeBytes = [long]64GB; TotalBytes = [long]64GB; DriveType = 'Removable'; Label = 'CLE' } }
        Mock Save-OpManifest {}
    }

    It 'copie l''outil et le dépôt retenu, écrit le manifeste filtré, garde les rapports, nettoie l''obsolète' {
        # Support déjà préparé le mois dernier : ancien fichier de l'outil, cumulative obsolète, rapport d'intervention.
        foreach ($f in 'offpatch.root', 'app\ancien.ps1', 'depot\files\zz\vieille.msu', 'depot\office\perpetualvl2021\v.cab') { Write-TestFile (Join-Path $script:support $f) }
        Write-TestFile (Join-Path $script:support 'rapports\2026-09-30_PC_SN.html') 20
        $r = Copy-OpSupport -Destination $script:support -Targets 'win11-x64' -OfficeSources 'current' -Root $script:tool -Confirm:$false
        $r.Cancelled | Should -BeFalse
        foreach ($f in 'Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE', 'app\gui\x.xaml', 'config\settings.json', 'tools\odt\.gitkeep', 'depot\files\aa\lcu.msu', 'depot\files\bb\def.exe', 'depot\office\current\Office\Data\v64.cab') {
            Join-Path $script:support $f | Should -Exist
        }
        (Get-Item (Join-Path $script:support 'depot\files\aa\lcu.msu')).Length | Should -Be 1000
        Join-Path $script:support 'app\ancien.ps1' | Should -Not -Exist -Because 'app en miroir'
        Join-Path $script:support 'logs' | Should -Not -Exist
        Join-Path $script:support 'depot\files\cc' | Should -Not -Exist -Because 'cible win10-x64 non retenue'
        Join-Path $script:support 'rapports\2026-09-30_PC_SN.html' | Should -Exist -Because 'rapports jamais mis en miroir'
        Join-Path $script:tool 'rapports\2026-09-30_PC_SN.html' | Should -Exist -Because 'rapport rapatrié sur le poste'
        @($r.Removed) | Should -Be @('depot\files\zz', 'depot\office\perpetualvl2021')
        @($r.Folders | ForEach-Object { $_.Path }) | Should -Be @('(racine)', 'app', 'config', 'tools', 'depot\files\aa', 'depot\files\bb', 'depot\office\current')
        @($r.Folders | Where-Object { $_.ExitCode -ge 8 }).Count | Should -Be 0
        Should -Invoke Save-OpManifest -Times 1 -Exactly -ParameterFilter {
            $GeneratedAt -eq '2026-10-18T07:40:58Z' -and $Path -eq [IO.Path]::Combine($script:support, 'depot\manifest.json') -and
            (@($Manifest.items | ForEach-Object { $_.id }) -join ',') -eq 'win11-x64-lcu,win11-x64-defender,office-current-16.0.1.1'
        }
    }

    It 'refuse avant toute écriture si le plan est refusé (dossiers étrangers à OffPatch)' {
        Write-TestFile (Join-Path $script:support 'app\photos.jpg')
        { Copy-OpSupport -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool -Confirm:$false } | Should -Throw '*dossiers app qui n''appartiennent pas à OffPatch*'
        Join-Path $script:support 'app\photos.jpg' | Should -Exist
        Join-Path $script:support 'offpatch.root' | Should -Not -Exist
    }

    It 'ne fait rien avec -WhatIf' {
        Copy-OpSupport -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool -WhatIf
        @(Get-ChildItem -LiteralPath $script:support -Recurse).Count | Should -Be 0
        Should -Invoke Save-OpManifest -Times 0 -Exactly
    }

    It 'robocopy en erreur (code 8 et plus) : arrêt, manifeste non écrit' {
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = 16; StdOut = "ERREUR 112`r`nEspace insuffisant"; StdErr = ''; Seconds = 1; TimedOut = $false } } -ParameterFilter { $ArgumentList[0] -like '*\config' }
        { Copy-OpSupport -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool -Confirm:$false } | Should -Throw '*Copie de config vers le support en échec (robocopy, code 16) : ERREUR 112 / Espace insuffisant*'
        Should -Invoke Save-OpManifest -Times 0 -Exactly
    }

    It 'bilan affiché par l''assistant' {
        $done = [pscustomobject]@{ Destination = 'F:\'; Cancelled = $false; Folders = @([pscustomobject]@{ Seconds = 90 }, [pscustomobject]@{ Seconds = 30 })
            Reports = @([pscustomobject]@{ Status = 'Copied' }, [pscustomobject]@{ Status = 'AlreadyPresent' }); Removed = @('depot\files\zz')
        }
        Get-OpSupportCopyText -Result $done | Should -Be 'Support F:\ préparé en 2 min : 2 copie(s), 1 rapport(s) rapatrié(s) sur ce poste, 1 dossier(s) obsolète(s) supprimé(s).'
        Get-OpSupportCopyText -Result ([pscustomobject]@{ Destination = 'F:\'; Cancelled = $true }) | Should -Match '^Préparation du support F:\\ annulée'
    }

    It 'script du runspace : Copy-OpSupport avec la sélection et le jeton d''annulation, sans confirmation' {
        function Initialize-OpSession { param($Kind, $Queue, $Root) }
        Mock Initialize-OpSession {}
        Mock Copy-OpSupport { 'copié' }
        $OpQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $OpCancel = (New-Object System.Threading.CancellationTokenSource).Token
        & $script:OpSupportCopyScript -Root 'X:\' -Destination 'F:\' -Targets @('win11-x64') -OfficeSources @('current') | Should -Be 'copié'
        Should -Invoke Initialize-OpSession -Times 1 -Exactly -ParameterFilter { $Kind -eq 'Depot' }
        Should -Invoke Copy-OpSupport -Times 1 -Exactly -ParameterFilter { $Destination -eq 'F:\' -and "$Targets" -eq 'win11-x64' -and "$OfficeSources" -eq 'current' -and $null -ne $CancellationToken -and $Confirm -eq $false }
    }

    It 'annulation : arrêt avant le dossier suivant, manifeste non écrit' {
        $source = New-Object System.Threading.CancellationTokenSource
        $source.Cancel()
        $r = Copy-OpSupport -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool -CancellationToken $source.Token -Confirm:$false
        $r.Cancelled | Should -BeTrue
        $r.Folders.Count | Should -Be 0
        Should -Invoke Save-OpManifest -Times 0 -Exactly
    }
}
