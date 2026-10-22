# Préparation d'un support (cahier des charges 7.4, étapes 1 à 3) : contenu filtré, système de fichiers, espace libre.
# Outil et dépôt factices dans TestDrive, volume du support simulé ; assistant chargé sans affichage (thread STA
# requis, sinon ces tests sont ignorés). Rien n'est copié.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fonctions factices du module : leurs paramètres servent aux filtres des simulacres.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Read-OpManifest', 'Format-OpSize', 'Get-OpVolumeInfo') { . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1") }
    . (Join-Path $repo 'app\module\OffPatch\Public\Get-OpSupportPlan.ps1')
    foreach ($name in 'MainWindow', 'Dialogs\PrepareSupport') { . (Join-Path $repo "app\gui\$name.ps1") }
    function Get-OpDepotSelection { param($Root) }

    # Outil factice : fichiers de l'outil, rapports et journaux (non copiés), cinq éléments au dépôt dont un incomplet
    # et deux qui partagent un fichier.
    function Initialize-TestTool([string]$Name) {
        $tool = Join-Path $TestDrive $Name
        foreach ($d in 'app\gui', 'config', 'tools\odt', 'depot\files\aa', 'depot\files\bb', 'depot\office\current', 'rapports', 'logs') { New-Item -ItemType Directory -Force -Path (Join-Path $tool $d) | Out-Null }
        foreach ($f in 'Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE', 'app\OffPatch.ps1', 'app\gui\x.xaml', 'config\settings.json', 'tools\odt\.gitkeep', 'rapports\r.html', 'logs\l.log') {
            [IO.File]::WriteAllText((Join-Path $tool $f), 'x')
        }
        [IO.File]::WriteAllBytes((Join-Path $tool 'depot\files\aa\lcu.msu'), (New-Object byte[] 1000))
        [IO.File]::WriteAllBytes((Join-Path $tool 'depot\files\bb\def.exe'), (New-Object byte[] 100))
        [IO.File]::WriteAllBytes((Join-Path $tool 'depot\office\current\v64.cab'), (New-Object byte[] 50))
        $items = @(
            '{ "id": "win11-x64-lcu", "category": "windows-lcu", "target": { "os": "win11", "arch": "x64" }, "files": [ { "path": "files/aa/lcu.msu", "sha256": "a", "size": 1000 } ] }'
            '{ "id": "win11-x64-defender", "category": "defender", "target": { "os": "win11", "arch": "x64" }, "files": [ { "path": "files/bb/def.exe", "sha256": "b", "size": 100 } ] }'
            '{ "id": "win10-x64-defender", "category": "defender", "target": { "os": "win10", "arch": "x64" }, "files": [ { "path": "files/bb/def.exe", "sha256": "b", "size": 100 } ] }'
            '{ "id": "win10-x64-lcu", "category": "windows-lcu", "target": { "os": "win10", "arch": "x64" }, "files": [ { "path": "files/cc/absent.msu", "sha256": "c", "size": 10 } ] }'
            '{ "id": "office-current-16.0.1.1", "category": "office-source", "channel": "Current", "folder": "office/current", "files": [ { "path": "office/current/v64.cab", "sha256": "d", "size": 50 } ] }')
        [IO.File]::WriteAllText((Join-Path $tool 'depot\manifest.json'), ('{ "schemaVersion": 1, "generatedAt": "2026-10-18T07:40:58Z", "items": [ ' + ($items -join ', ') + ' ] }'))
        $tool
    }
    function Get-TestVolume([string]$FileSystem = 'exFAT', [long]$Free = 64GB, [long]$Total = 64GB, [bool]$Ready = $true, [string]$Root = 'S:\') {
        [pscustomobject]@{ Root = $Root; IsReady = $Ready; FileSystem = $FileSystem; FreeBytes = $Free; TotalBytes = $Total; DriveType = 'Removable'; Label = 'CLE' }
    }
    # Manifeste factice réduit aux champs du filtrage : lu tel quel, sans la validation complète de Read-OpManifest.
    Mock Read-OpManifest { [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    $script:tool = Initialize-TestTool 'outil'
    $script:support = Join-Path $TestDrive 'support'
    New-Item -ItemType Directory -Force -Path $script:support | Out-Null
}

Describe 'Get-OpSupportPlan' {
    BeforeEach { Mock Get-OpVolumeInfo { Get-TestVolume } }

    It 'garde l''outil et les éléments des cibles et sources retenues, fichier partagé compté une fois' {
        $p = Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64', 'win10-x64' -OfficeSources 'current' -Root $script:tool
        @($p.Items | ForEach-Object { $_.id }) | Should -Be @('win11-x64-lcu', 'win11-x64-defender', 'win10-x64-defender', 'office-current-16.0.1.1')
        $p.DepotBytes | Should -Be 1150
        $paths = @($p.Files | ForEach-Object { $_.Path })
        $paths | Should -Contain 'Lancer-OffPatch.cmd'
        $paths | Should -Contain 'app\gui\x.xaml'
        $paths | Should -Contain 'tools\odt\.gitkeep'
        $paths | Should -Contain 'depot\office\current\v64.cab'
        @($paths | Where-Object { $_ -eq 'depot\files\bb\def.exe' }).Count | Should -Be 1
        @($paths | Where-Object { $_ -like 'rapports*' -or $_ -like 'logs*' -or $_ -eq 'depot\manifest.json' }).Count | Should -Be 0 -Because 'rapports, journaux et manifeste complet ne sont pas copiés tels quels'
        $p.ToolBytes | Should -Be 8
        $p.ToCopyBytes | Should -Be 1158
        $p.CanPrepare | Should -BeTrue
    }

    It 'écarte un élément incomplet au dépôt, avec un avertissement' {
        $p = Get-OpSupportPlan -Destination $script:support -Targets 'win10-x64' -OfficeSources @() -Root $script:tool
        @($p.Items | ForEach-Object { $_.id }) | Should -Be @('win10-x64-defender')
        $p.Warnings | Should -Match 'win10-x64-lcu : 1 fichier\(s\) absent\(s\) ou incomplet\(s\)'
    }

    It 'système de fichiers <FileSystem> : accepté <Ok>' -TestCases @(
        @{ FileSystem = 'FAT32'; Ok = $false }, @{ FileSystem = 'FAT'; Ok = $false }, @{ FileSystem = 'NTFS'; Ok = $true }, @{ FileSystem = 'exFAT'; Ok = $true }
    ) {
        param($FileSystem, $Ok)
        Mock Get-OpVolumeInfo { Get-TestVolume -FileSystem $FileSystem }
        $p = Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool
        $p.CanPrepare | Should -Be $Ok
        if (-not $Ok) { $p.Blocking | Should -Match "Système de fichiers $FileSystem refusé : NTFS ou exFAT requis" }
    }

    It 'espace : refus s''il manque de la place, fichiers déjà présents et de la bonne taille non comptés' {
        Mock Get-OpVolumeInfo { Get-TestVolume -Free 500 }
        $p = Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool
        $p.CanPrepare | Should -BeFalse
        $p.Blocking | Should -Match '^Espace insuffisant sur S:'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:support 'depot\files\aa') | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $script:support 'depot\files\aa\lcu.msu'), (New-Object byte[] 1000))
        $p = Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool
        $p.ToCopyBytes | Should -Be 108
        $p.CanPrepare | Should -BeTrue
    }

    It 'refuse un lecteur absent, le lecteur de l''outil et une sélection vide' {
        Mock Get-OpVolumeInfo { Get-TestVolume -Ready $false }
        (Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool).Blocking | Should -Match 'absent ou pas prêt'
        Mock Get-OpVolumeInfo { Get-TestVolume -Root ([IO.Path]::GetPathRoot($script:tool)) }
        (Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool).Blocking | Should -Match 'autre lecteur que celui de l.outil'
        Mock Get-OpVolumeInfo { Get-TestVolume }
        (Get-OpSupportPlan -Destination $script:support -Targets @() -OfficeSources @() -Root $script:tool).Blocking | Should -Match '^Rien à embarquer'
    }

    It 'avertit quand le support fait moins du double du dépôt retenu' {
        Mock Get-OpVolumeInfo { Get-TestVolume -Total 2000 }
        (Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool).Warnings | Should -Match 'peu de marge'
        Mock Get-OpVolumeInfo { Get-TestVolume -Total 2200 }
        (Get-OpSupportPlan -Destination $script:support -Targets 'win11-x64' -OfficeSources @() -Root $script:tool).Warnings | Should -BeNullOrEmpty
    }

    It 'sélection par défaut : cibles cochées et sources actives du dépôt' {
        Mock Get-OpDepotSelection { [pscustomobject]@{ Targets = @('win11-x64'); OfficeSources = @([pscustomobject]@{ Id = 'current'; Enabled = $false }) } }
        $p = Get-OpSupportPlan -Destination $script:support -Root $script:tool
        $p.Targets | Should -Be @('win11-x64')
        $p.OfficeSources.Count | Should -Be 0
    }
}

Describe 'Get-OpVolumeInfo' {
    It 'lit le volume du dossier de test' {
        $v = Get-OpVolumeInfo -Path $TestDrive
        $v.IsReady | Should -BeTrue
        $v.Root | Should -Be ([IO.Path]::GetPathRoot($TestDrive))
        $v.TotalBytes | Should -BeGreaterThan 0
    }
}

Describe 'Assistant « Préparer un support »' {
    It 'propose les lecteurs prêts, amovibles ou fixes, sauf ceux du système et de l''outil' {
        $drives = @(
            [pscustomobject]@{ Name = 'F:\'; IsReady = $true; DriveType = 'Removable'; VolumeLabel = 'CLE'; DriveFormat = 'exFAT'; AvailableFreeSpace = [long]50GB; TotalSize = [long]58GB }
            [pscustomobject]@{ Name = 'G:\'; IsReady = $false; DriveType = 'Removable'; VolumeLabel = ''; DriveFormat = ''; AvailableFreeSpace = 0; TotalSize = 0 }
            [pscustomobject]@{ Name = 'H:\'; IsReady = $true; DriveType = 'CDRom'; VolumeLabel = 'DVD'; DriveFormat = 'UDF'; AvailableFreeSpace = 0; TotalSize = 1 }
            [pscustomobject]@{ Name = "$($env:SystemDrive)\"; IsReady = $true; DriveType = 'Fixed'; VolumeLabel = 'OS'; DriveFormat = 'NTFS'; AvailableFreeSpace = 1; TotalSize = 1 }
            [pscustomobject]@{ Name = 'X:\'; IsReady = $true; DriveType = 'Fixed'; VolumeLabel = ''; DriveFormat = 'NTFS'; AvailableFreeSpace = [long]10GB; TotalSize = [long]20GB }
            [pscustomobject]@{ Name = 'T:\'; IsReady = $true; DriveType = 'Fixed'; VolumeLabel = 'OUTIL'; DriveFormat = 'NTFS'; AvailableFreeSpace = 1; TotalSize = 1 })
        $list = @(Get-OpSupportDriveList -Root 'T:\OffPatch' -Drives $drives)
        @($list | ForEach-Object { $_.Root }) | Should -Be @('F:\', 'X:\')
        $list[0].Label | Should -Match '^F:. — CLE \(exFAT, 50[.,]0 Go libres sur 58[.,]0 Go\)$'
        $list[1].Label | Should -Match 'sans nom'
    }

    It 'textes : résumé, refus, avertissements' {
        $plan = [pscustomobject]@{ Items = @(1, 2); DepotBytes = [long]9GB; ToolBytes = [long]8MB; ToCopyBytes = [long]9GB; Volume = (Get-TestVolume -Free ([long]20GB)); Blocking = @('a', 'b'); Warnings = @() }
        $t = Get-OpSupportPlanText -Plan $plan
        $t.Summary | Should -Match '^Dépôt retenu : 2 élément\(s\), 9[.,]00 Go ; outil : 8[.,]0 Mo\. Support S:. : exFAT, 20[.,]0 Go libres ; à copier : 9[.,]00 Go\.$'
        $t.Blocking | Should -Match '^a\r?\nb$'
        $t.Warnings | Should -BeNullOrEmpty
    }

    Context 'fenêtre' -Skip:$script:noSta {
        BeforeAll {
            Mock Get-OpDepotSelection { [pscustomobject]@{ AvailableTargets = @('win11-x64', 'win10-x64'); Targets = @('win11-x64'); OfficeSources = @([pscustomobject]@{ Id = 'current'; Enabled = $true; Languages = @('fr-fr') }) } }
            Mock Get-OpVolumeInfo { Get-TestVolume -FileSystem 'FAT32' }
            # Lecteur inconnu du PC qui exécute les tests (la CI n'a pas de F:) : les contrôles ne doivent pas en dépendre.
            $drives = @([pscustomobject]@{ Name = 'Q:\'; IsReady = $true; DriveType = 'Removable'; VolumeLabel = 'CLE'; DriveFormat = 'FAT32'; AvailableFreeSpace = [long]20GB; TotalSize = [long]29GB })
            $script:d = Import-OpPrepareSupportWindow -Root $script:tool -Drives $drives
        }
        AfterAll { $script:d.Window.Close() }

        It 'coche la sélection du dépôt, choisit le premier lecteur et affiche le refus du FAT32' {
            $c = $script:d.Controls
            @($c.SupportTargets.Children | ForEach-Object { "$($_.Content)=$($_.IsChecked)" }) | Should -Be @('win11-x64=True', 'win10-x64=False')
            $c.SupportSources.Children[0].Content | Should -Be 'current (fr-fr)'
            $c.SupportDrive.SelectedItem.Root | Should -Be 'Q:\'
            $c.SupportBlocking.Visibility | Should -Be 'Visible'
            $c.SupportBlockingText.Text | Should -Match 'FAT32 refusé'
            $c.BtnSupportPrepare.IsEnabled | Should -BeFalse
        }

        It 'recalcule après un changement de sélection' {
            $c = $script:d.Controls
            $c.SupportTargets.Children[1].IsChecked = $true
            Show-OpSupportView -Dialog $script:d
            @($script:d.Plan.Targets) | Should -Be @('win11-x64', 'win10-x64')
        }
    }
}
