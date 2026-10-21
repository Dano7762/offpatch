# Onglet « Dépôt » (cahier des charges 6.1, 6.3, 7, 9) : sélection des cibles et des sources Office (fichiers de
# config copiés dans le TestDrive), inventaire du dépôt (dépôt factice), avancement pour l'interface, affichage sur
# une vraie fenêtre chargée sans affichage (thread STA requis, sinon ces tests sont ignorés). Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Paramètres des cas de test utilisés dans le bloc passé à Should -Throw, non vu par l''analyse.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $repo 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }
    foreach ($name in 'MainWindow', 'Background', 'Header', 'DepotTab') { . (Join-Path $repo "app\gui\$name.ps1") }

    function Initialize-TestTool([string]$Name) {
        $tool = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path $tool | Out-Null
        Copy-Item -Path (Join-Path $repo 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $repo 'offpatch.root') -Destination $tool
        $tool
    }
    function Get-TextLine([string]$Path) { [System.IO.File]::ReadAllText($Path) -split "`n" }
    function Get-Source([string]$Id, [bool]$Enabled, [string[]]$Languages) { [pscustomobject]@{ Id = $Id; Enabled = $Enabled; Languages = $Languages } }
}

Describe 'Get-OpDepotSelection' {
    It 'cibles possibles (catalog-queries.json), cochées (settings.json), sources actives par défaut' {
        $tool = Initialize-TestTool 'sel'
        $s = Get-OpDepotSelection -Root $tool
        $s.AvailableTargets | Should -Be @('win11-x64', 'win11-arm64', 'win10-x64')
        $s.Targets | Should -Be @('win11-x64', 'win11-arm64', 'win10-x64')
        @($s.OfficeSources | ForEach-Object { $_.Id }) | Should -Be @('current', 'perpetualvl2024', 'perpetualvl2021')
        @($s.OfficeSources | Where-Object { -not $_.Enabled }).Count | Should -Be 0
        $s.OfficeSources[0].Languages | Should -Be @('fr-fr', 'en-us')
    }
}

Describe 'Set-OpDepotSelection' {
    BeforeEach { Mock Write-OpLog {} }

    It 'ne change que la ligne targets de settings.json, fins de ligne et absence de BOM conservées' {
        $tool = Initialize-TestTool 'targets'
        $path = Join-Path $tool 'config\settings.json'
        $before = Get-TextLine $path
        $r = Set-OpDepotSelection -Targets 'win11-x64', 'win10-x64' -Root $tool -Confirm:$false
        $r.Targets | Should -Be @('win11-x64', 'win10-x64')
        $after = Get-TextLine $path
        $after.Count | Should -Be $before.Count
        @(for ($i = 0; $i -lt $after.Count; $i++) { if ($after[$i] -cne $before[$i]) { $after[$i] } }) | Should -Be @('  "targets": ["win11-x64", "win10-x64"],')
        [System.IO.File]::ReadAllBytes($path)[0] | Should -Be 0x7B -Because 'pas de BOM'
        [System.IO.File]::ReadAllText($path) | Should -Not -Match "`r`n"
        Test-Path "$path.tmp" | Should -BeFalse
    }

    It 'désactive une source par "enabled": false avant ses langues, puis la réactive, CRLF conservé' {
        $tool = Initialize-TestTool 'sources'
        $path = Join-Path $tool 'config\office\sources.json'
        $original = [System.IO.File]::ReadAllText($path)
        Set-OpDepotSelection -Targets 'win11-x64', 'win11-arm64', 'win10-x64' -OfficeSources @(Get-Source 'perpetualvl2024' $false @('fr-fr')) -Root $tool -Confirm:$false | Out-Null
        $text = [System.IO.File]::ReadAllText($path)
        $text | Should -Match '"folder": "office/perpetualvl2024",\r\n      "enabled": false,\r\n      "languages": \["fr-fr"\]'
        ($text -split "`n").Count | Should -Be (($original -split "`n").Count + 1)
        (Get-OpDepotSelection -Root $tool).OfficeSources[1].Enabled | Should -BeFalse
        Set-OpDepotSelection -Targets 'win11-x64', 'win11-arm64', 'win10-x64' -OfficeSources @(Get-Source 'perpetualvl2024' $true @('fr-fr')) -Root $tool -Confirm:$false | Out-Null
        [System.IO.File]::ReadAllText($path) | Should -Match '"enabled": true,\r\n      "languages"'
        (Get-OpDepotSelection -Root $tool).OfficeSources[1].Enabled | Should -BeTrue
    }

    It 'change les langues d''une source sans toucher aux autres' {
        $tool = Initialize-TestTool 'langues'
        Set-OpDepotSelection -Targets 'win11-x64', 'win11-arm64', 'win10-x64' -OfficeSources @(Get-Source 'current' $true @('fr-fr', 'de-de')) -Root $tool -Confirm:$false | Out-Null
        $s = Get-OpDepotSelection -Root $tool
        $s.OfficeSources[0].Languages | Should -Be @('fr-fr', 'de-de')
        $s.OfficeSources[2].Languages | Should -Be @('fr-fr')
    }

    It 'refuse <Cas> sans rien écrire' -TestCases @(
        @{ Cas = 'une langue mal formée'; Targets = @('win11-x64'); Sources = @(@{ Id = 'current'; Enabled = $true; Languages = @('fr') }); Pattern = '*langue*fr*invalide*' }
        @{ Cas = 'une cible inconnue'; Targets = @('win12-x64'); Sources = @(); Pattern = '*cible inconnue*win12-x64*' }
        @{ Cas = 'une source inconnue'; Targets = @('win11-x64'); Sources = @(@{ Id = 'beta'; Enabled = $true; Languages = @('fr-fr') }); Pattern = '*source beta introuvable*' }
        @{ Cas = 'une valeur qui casserait le JSON'; Targets = @('win11-x64"'); Sources = @(); Pattern = '*Valeur refusée*' }
        @{ Cas = 'aucune langue'; Targets = @('win11-x64'); Sources = @(@{ Id = 'current'; Enabled = $true; Languages = @() }); Pattern = '*aucune langue*' }
    ) {
        param($Targets, $Sources, $Pattern)
        $tool = Initialize-TestTool ([guid]::NewGuid().ToString())
        $settings = [System.IO.File]::ReadAllText((Join-Path $tool 'config\settings.json'))
        $sourcesText = [System.IO.File]::ReadAllText((Join-Path $tool 'config\office\sources.json'))
        $objects = @($Sources | ForEach-Object { [pscustomobject]$_ })
        { Set-OpDepotSelection -Targets $Targets -OfficeSources $objects -Root $tool -Confirm:$false } | Should -Throw $Pattern
        [System.IO.File]::ReadAllText((Join-Path $tool 'config\settings.json')) | Should -BeExactly $settings
        [System.IO.File]::ReadAllText((Join-Path $tool 'config\office\sources.json')) | Should -BeExactly $sourcesText
    }

    It 'n''écrit rien avec -WhatIf' {
        $tool = Initialize-TestTool 'whatif'
        $settings = [System.IO.File]::ReadAllText((Join-Path $tool 'config\settings.json'))
        Set-OpDepotSelection -Targets 'win11-x64' -Root $tool -WhatIf | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $tool 'config\settings.json')) | Should -BeExactly $settings
    }
}

Describe 'Sources Office désactivées' {
    It 'Test-OpConfiguration refuse un enabled qui n''est pas booléen' {
        $tool = Initialize-TestTool 'enabled'
        $c = Get-OpConfiguration -Root $tool
        $c.OfficeSources.sources[0] | Add-Member -NotePropertyName enabled -NotePropertyValue 'non'
        @(Test-OpConfiguration -Configuration $c) | Should -Contain 'sources.json, current : enabled doit valoir true ou false.'
    }

    It 'Get-OpOfficeDownloadXml ne génère rien pour une source désactivée' {
        $tool = Initialize-TestTool 'xml'
        $c = Get-OpConfiguration -Root $tool
        $c.OfficeSources.sources[1] | Add-Member -NotePropertyName enabled -NotePropertyValue $false
        @(Get-OpOfficeDownloadXml -Configuration $c -Root $tool | ForEach-Object { $_.Id }) | Should -Be @('current', 'perpetualvl2021')
    }
}

Describe 'Get-OpDepotInventory' {
    It 'une ligne par élément, taille, état des fichiers, total sans double compte' {
        $tool = Initialize-TestTool 'inventaire'
        $depot = Join-Path $tool 'depot'
        foreach ($rel in 'files\a\lcu.msu', 'files\b\cp.msu', 'office\current\v64.cab') {
            New-Item -ItemType Directory -Force -Path (Split-Path (Join-Path $depot $rel)) | Out-Null
        }
        [System.IO.File]::WriteAllBytes((Join-Path $depot 'files\a\lcu.msu'), (New-Object byte[] 100))
        [System.IO.File]::WriteAllBytes((Join-Path $depot 'files\b\cp.msu'), (New-Object byte[] 20))
        $script:testManifest = [pscustomobject]@{
            schemaVersion = 1; generatedAt = '2026-10-18T07:40:58Z'; items = @(
                [pscustomobject]@{ id = 'win11-x64-lcu-KB1'; category = 'windows-lcu'; kb = 'KB1'; releaseDate = '2026-10-13'; target = [pscustomobject]@{ os = 'win11'; arch = 'x64' }
                    files = @([pscustomobject]@{ path = 'files/a/lcu.msu'; size = 100 }, [pscustomobject]@{ path = 'files/b/cp.msu'; size = 20 }) }
                [pscustomobject]@{ id = 'win11-arm64-checkpoint-KB2'; category = 'windows-checkpoint'; kb = 'KB2'; target = [pscustomobject]@{ os = 'win11'; arch = 'arm64' }
                    files = @([pscustomobject]@{ path = 'files/b/cp.msu'; size = 30 }) }
                [pscustomobject]@{ id = 'office-current-16.0.1.1'; category = 'office-source'; channel = 'Current'; version = '16.0.1.1'
                    files = @([pscustomobject]@{ path = 'office/current/v64.cab'; size = 5 }) })
        }
        Mock Read-OpManifest { $script:testManifest }
        $inv = Get-OpDepotInventory -Root $tool
        @($inv.Items | ForEach-Object { "$($_.Target)|$($_.CategoryLabel)|$($_.Detail)|$($_.ReleaseDate)|$($_.SizeBytes)|$($_.Integrity)" }) | Should -Be @(
            'win11-x64|Cumulative Windows|KB1|2026-10-13|120|Complet'
            'win11-arm64|Cumulative de base (checkpoint)|KB2||30|1 fichier(s) de taille différente'
            'Office Current|Office|16.0.1.1||5|1 fichier(s) absent(s)')
        $inv.TotalBytes | Should -Be 135 -Because 'cp.msu partagé compté une fois'
        $inv.Status.State | Should -Be 'Ok'
        $inv.Items[0].Size | Should -Match 'Mo$'
    }

    It 'manifeste illisible : aucune ligne' {
        $tool = Initialize-TestTool 'illisible'
        Mock Read-OpManifest { throw 'JSON invalide' }
        $inv = Get-OpDepotInventory -Root $tool
        $inv.Items.Count | Should -Be 0
        $inv.Status.State | Should -Be 'Unreadable'
    }
}

Describe 'Write-OpProgress pour l''interface' {
    It 'dépose l''avancement dans la file de messages, sans console' {
        $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:OpLog = [pscustomobject]@{ Path = (Join-Path $TestDrive 'p.log'); Level = 'INFO'; Queue = $queue; Console = $false }
        try {
            Mock Write-Host {}
            Write-OpProgress '  BITS :' -Bytes 1GB -TotalBytes 4GB
            $m = $null
            $queue.TryDequeue([ref]$m) | Should -BeTrue
            $m.Kind | Should -Be 'Progress'
            $m.Message | Should -Match '^BITS : 1,00 Go / 4,00 Go \(25 %\)$'
            Should -Invoke Write-Host -Times 0 -Exactly
        } finally { $script:OpLog = $null }
    }
}

Describe 'Get-OpDepotStatusText' {
    It 'date et alerte selon l''état du dépôt' {
        $ok = [pscustomobject]@{ State = 'Ok'; GeneratedAt = [datetime]'2026-10-18'; AgeDays = 1; StaleDays = 35; Error = $null }
        (Get-OpDepotStatusText -Status $ok).Date | Should -Be 'Dépôt du 18/10/2026 (il y a 1 jour)'
        (Get-OpDepotStatusText -Status $ok).Alert | Should -BeNullOrEmpty
        $ok.State = 'Stale'
        (Get-OpDepotStatusText -Status $ok).Alert | Should -Match 'plus de 35 jours'
    }
}

Describe 'Onglet Dépôt (fenêtre)' -Skip:$script:noSta {
    BeforeAll {
        $script:ui = Import-OpMainWindow
        $selection = [pscustomobject]@{
            AvailableTargets = @('win11-x64', 'win11-arm64', 'win10-x64'); Targets = @('win11-x64', 'win10-x64')
            OfficeSources = @(
                [pscustomobject]@{ Id = 'current'; Channel = 'Current'; Enabled = $true; Languages = @('fr-fr', 'en-us') }
                [pscustomobject]@{ Id = 'perpetualvl2024'; Channel = 'PerpetualVL2024'; Enabled = $false; Languages = @('fr-fr') })
        }
        $inventory = [pscustomobject]@{
            Status = [pscustomobject]@{ State = 'Ok'; GeneratedAt = [datetime]'2026-10-18'; AgeDays = 3; StaleDays = 35; Error = $null }
            Items = @([pscustomobject]@{ Target = 'win11-x64'; CategoryLabel = 'Cumulative Windows'; Detail = 'KB1'; ReleaseDate = '2026-10-13'; Size = '4,45 Go'; Integrity = 'Complet' })
            TotalSize = '4,45 Go'
        }
        $script:view = [pscustomobject]@{ Inventory = $inventory; Selection = $selection }
    }
    AfterAll { $script:ui.Window.Close() }

    It 'affiche résumé, cibles, sources et contenu ; rien à enregistrer au départ' {
        $c = $script:ui.Controls
        Show-OpDepotView -Controls $c -View $script:view
        $c.DepotSummary.Text | Should -Be 'Dépôt du 18/10/2026 (il y a 3 jours) · 1 élément(s) · 4,45 Go'
        $c.DepotAlert.Visibility | Should -Be 'Collapsed'
        @($c.DepotTargets.Children | ForEach-Object { "$($_.Content)=$($_.IsChecked)" }) | Should -Be @('win11-x64=True', 'win11-arm64=False', 'win10-x64=True')
        $c.DepotSources.Children.Count | Should -Be 2
        @($c.DepotItems.ItemsSource).Count | Should -Be 1
        $c.BtnSaveSelection.IsEnabled | Should -BeFalse
    }

    It 'relit la sélection saisie : cases et langues normalisées' {
        $c = $script:ui.Controls
        Show-OpDepotView -Controls $c -View $script:view
        $c.DepotTargets.Children[1].IsChecked = $true
        $second = @($c.DepotSources.Children[1].Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })[0]
        $second.IsChecked = $true
        $second.Tag.Languages.Text = 'FR-fr ; de-DE,fr-fr'
        $entered = Get-OpDepotSelectionInput -Controls $c
        $entered.Targets | Should -Be @('win11-x64', 'win11-arm64', 'win10-x64')
        $entered.OfficeSources[1].Enabled | Should -BeTrue
        $entered.OfficeSources[1].Languages | Should -Be @('fr-fr', 'de-de')
        $entered.OfficeSources[0].Languages | Should -Be @('fr-fr', 'en-us')
        $c.BtnSaveSelection.IsEnabled | Should -BeTrue -Because 'la saisie des langues active l''enregistrement'
    }

    It 'grise les commandes pendant un traitement, Annuler seulement s''il est annulable' {
        $c = $script:ui.Controls
        Set-OpDepotBusy -Controls $c -Busy $true -Cancellable $true -Confirm:$false
        $c.BtnDepotUpdate.IsEnabled | Should -BeFalse
        $c.BtnDepotCancel.IsEnabled | Should -BeTrue
        Set-OpDepotBusy -Controls $c -Busy $true -Confirm:$false
        $c.BtnDepotCancel.IsEnabled | Should -BeFalse
        Set-OpDepotBusy -Controls $c -Busy $false -Confirm:$false
        $c.BtnDepotUpdate.IsEnabled | Should -BeTrue
        $c.BtnDepotCancel.IsEnabled | Should -BeFalse
    }
}
