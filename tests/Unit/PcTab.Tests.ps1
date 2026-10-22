# Onglet « Ce PC » (cahier des charges 8.7, 9) : textes du bandeau, tableau des étapes, installation de la sélection
# (fonctions du module simulées), affichage sur une vraie fenêtre chargée sans affichage (thread STA requis, sinon
# ces tests sont ignorés). Rien n'est installé ni redémarré.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fonctions factices du module : leurs paramètres servent aux filtres des simulacres.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Fonctions factices du module : -Confirm accepté comme par les vraies, sans effet.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'MainWindow', 'Background', 'PcTab') { . (Join-Path $repo "app\gui\$name.ps1") }

    function Get-TestRow([string]$Id, [string]$Category, [string]$State = 'Pending', [bool]$RebootAfter = $false) {
        $labels = @{ Pending = 'À installer'; UpToDate = 'À jour'; NotApplicable = 'Non applicable' }
        $categories = @{ 'defender' = 'Définitions Defender'; 'windows-lcu' = 'Cumulative Windows'; 'dotnet' = '.NET Framework' }
        [pscustomobject]@{ Sequence = 1; Id = $Id; Category = $Category; CategoryLabel = $categories[$Category]; State = $State; StateLabel = $labels[$State]; Reason = "motif $Id"; Available = $null; RebootAfter = $RebootAfter }
    }
    function Get-TestView([hashtable]$Info = @{}, [object[]]$Checks = @(), [object[]]$Plan) {
        $i = [ordered]@{
            ComputerName = 'PC-ATELIER'; Caption = 'Microsoft Windows 11 Famille'; DisplayVersion = '25H2'; CurrentBuild = 26200; Ubr = 8037
            Architecture = 'x64'; Family = 'Windows11'; Manufacturer = 'Fabricant'; Model = 'Modèle 14'; SerialNumber = 'SN1'
            SystemDrive = 'C:'; FreeSpaceBytes = [long]60GB; Power = [pscustomobject]@{ OnBattery = $false; BatteryPercent = $null }
            Esu = $null; Office = $null
        }
        foreach ($k in $Info.Keys) { $i[$k] = $Info[$k] }
        if ($null -eq $Plan) {
            $Plan = @((Get-TestRow 'def' 'defender'), (Get-TestRow 'lcu' 'windows-lcu' -RebootAfter $true), (Get-TestRow 'net' 'dotnet' 'UpToDate'),
                [pscustomobject]@{ Sequence = 4; Id = $null; Category = 'office-source'; CategoryLabel = 'Office'; State = 'NotApplicable'; StateLabel = 'Non applicable'; Reason = 'Aucun Office Click-to-Run.'; Available = $null; RebootAfter = $false })
        }
        $sources = [pscustomobject]@{ sources = @([pscustomobject]@{ id = 'current'; channel = 'Current'; languages = @('fr-fr', 'en-us'); installedChannelIds = @('492350f6-3a01-4f97-b9c0-c7c6ddf67d60') }) }
        [pscustomobject]@{ Info = [pscustomobject]$i; Checks = $Checks; Plan = $Plan; OfficeSources = $sources }
    }
}

Describe 'ConvertTo-OpPcStepTable' {
    It 'une ligne par étape, étapes à installer cochées, les autres non cochables' {
        $t = ConvertTo-OpPcStepTable -Plan (Get-TestView).Plan
        $t.Rows.Count | Should -Be 4
        @($t.Rows | ForEach-Object { $_.Selected }) | Should -Be @($true, $true, $false, $false)
        @($t.Rows | ForEach-Object { $_.Pending }) | Should -Be @($true, $true, $false, $false)
        $t.Rows[1].CategoryLabel | Should -Be 'Cumulative Windows'
        $t.Rows[1].RebootAfter | Should -BeTrue
        $t.Rows[0].Detail | Should -Be 'def' -Because 'sans version disponible, l''identifiant'
        $t.Rows[3].CategoryLabel | Should -Be 'Office'
    }

    It 'tolère un plan vide' {
        (ConvertTo-OpPcStepTable -Plan @()).Rows.Count | Should -Be 0
    }
}

Describe 'Get-OpPcSummary' {
    It 'bandeau système : PC, version, build et UBR, fabricant, modèle, série, espace libre, alimentation' {
        $s = Get-OpPcSummary -View (Get-TestView)
        $s.Title | Should -Be 'PC-ATELIER — Microsoft Windows 11 Famille 25H2, build 26200.8037, x64'
        $s.Detail | Should -Match 'Fabricant : Fabricant.*Modèle : Modèle 14.*N° de série : SN1.*Espace libre sur C: : 60.0 Go.*Alimentation : secteur'
        $s.Detail | Should -Not -Match 'ESU'
        $s.CanInstall | Should -BeTrue
        $s.RebootPending | Should -BeFalse
    }

    It 'Windows 10 sur batterie : statut ESU et charge' {
        $s = Get-OpPcSummary -View (Get-TestView @{ Family = 'Windows10'; Power = [pscustomobject]@{ OnBattery = $true; BatteryPercent = 42 } })
        $s.Detail | Should -Match 'batterie \(42 %\).*ESU : absent ou indétectable'
        $s = Get-OpPcSummary -View (Get-TestView @{ Family = 'Windows10'; Esu = [pscustomobject]@{ Status = 'Active'; Year = 2 } })
        $s.Detail | Should -Match 'ESU : actif \(année 2\)'
    }

    It 'contrôles qui ne sont pas Ok, bloquants en tête ; pas d''installation sur un contrôle bloquant' {
        $checks = @(
            [pscustomobject]@{ Id = 'Elevation'; Label = 'Droits administrateur'; Result = 'Blocking'; Message = 'Session non élevée.' }
            [pscustomobject]@{ Id = 'PendingReboot'; Label = 'Redémarrage en attente'; Result = 'Warning'; Message = 'CBS' }
            [pscustomobject]@{ Id = 'Network'; Label = 'Réseau'; Result = 'Ok'; Message = 'hors ligne' })
        $s = Get-OpPcSummary -View (Get-TestView -Checks $checks)
        $s.Checks | Should -Be @('Bloquant — Droits administrateur : Session non élevée.', 'Redémarrage en attente : CBS')
        $s.RebootPending | Should -BeTrue
        $s.CanInstall | Should -BeFalse
    }

    It 'rien à installer : installation impossible' {
        (Get-OpPcSummary -View (Get-TestView -Plan @(Get-TestRow 'def' 'defender' 'UpToDate'))).CanInstall | Should -BeFalse
    }

    It 'bloc Office : <Cas>' -TestCases @(
        @{ Cas = 'aucun Office'; Office = $null; Pattern = '^Office : aucun Office Click-to-Run\. Non applicable : Aucun Office Click-to-Run\.$' }
        @{ Cas = 'Office détecté, source du dépôt'; Office = [pscustomobject]@{ Products = @('O365HomePremRetail'); ChannelId = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'; Languages = @('fr-fr'); Version = '16.0.1.1' }
            Pattern = 'O365HomePremRetail, canal Current, langues fr-fr, version 16\.0\.1\.1\. Source du dépôt : current \(fr-fr, en-us\)\.' }
        @{ Cas = 'canal absent du dépôt'; Office = [pscustomobject]@{ Products = @('ProPlusRetail'); ChannelId = 'inconnu'; Languages = @('fr-fr'); Version = '16.0.1.1' }
            Pattern = 'canal inconnu.*version 16\.0\.1\.1\. Non applicable' }
    ) {
        param($Office, $Pattern)
        (Get-OpPcSummary -View (Get-TestView @{ Office = $Office })).Office | Should -Match $Pattern
    }
}

Describe 'Installation de la sélection (script du runspace)' {
    BeforeAll {
        function Initialize-OpSession { param($Kind, $Queue, $Root) }
        function Invoke-OpInstallStep { [CmdletBinding(SupportsShouldProcess)] param($StepId, $Root) }
        function Write-OpInstallReport { [CmdletBinding(SupportsShouldProcess)] param($Root) }
    }
    BeforeEach {
        $OpQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Mock Initialize-OpSession {}
        Mock Write-OpInstallReport { 'X:\rapports\r.html' }
        Mock Invoke-OpInstallStep { [pscustomobject]@{ Id = $StepId; State = 'UpToDate'; RebootAfter = ($StepId -eq 'lcu') } }
    }

    It 'installe dans l''ordre, s''arrête après une étape réussie qui demande un redémarrage, puis écrit le rapport' {
        $r = & $script:OpPcInstallScript -Root 'X:\' -Ids @('def', 'lcu', 'net')
        @($r.Results | ForEach-Object { $_.Id }) | Should -Be @('def', 'lcu')
        $r.ReportPath | Should -Be 'X:\rapports\r.html'
        Should -Invoke Invoke-OpInstallStep -Times 0 -Exactly -ParameterFilter { $StepId -eq 'net' }
        Should -Invoke Write-OpInstallReport -Times 1 -Exactly
        $m = $null
        $steps = @(); while ($OpQueue.TryDequeue([ref]$m)) { $steps += $m }
        @($steps | ForEach-Object { "$($_.Index)/$($_.Count) $($_.Id)" }) | Should -Be @('0/3 def', '1/3 lcu')
    }

    It 'continue après une étape en erreur ou refusée, et le signale dans la file' {
        Mock Invoke-OpInstallStep { [pscustomobject]@{ Id = $StepId; State = 'Error'; RebootAfter = $true } } -ParameterFilter { $StepId -eq 'lcu' }
        Mock Invoke-OpInstallStep { throw 'contrôle préalable bloquant' } -ParameterFilter { $StepId -eq 'def' }
        $r = & $script:OpPcInstallScript -Root 'X:\' -Ids @('def', 'lcu', 'net')
        @($r.Results | ForEach-Object { "$($_.Id) $($_.State)" }) | Should -Be @('def Error', 'lcu Error', 'net UpToDate')
        $lines = @(); $m = $null; while ($OpQueue.TryDequeue([ref]$m)) { if ($m.PSObject.Properties['Line']) { $lines += $m.Line } }
        $lines | Should -Match '\[ERROR\] Étape def non exécutée : contrôle préalable bloquant'
    }
}

Describe 'Restart-OpPc' {
    It 'redémarre avec -Confirm:$false, rien avec -WhatIf' {
        Mock Restart-Computer {}
        Restart-OpPc -WhatIf
        Should -Invoke Restart-Computer -Times 0 -Exactly
        Restart-OpPc -Confirm:$false
        Should -Invoke Restart-Computer -Times 1 -Exactly -ParameterFilter { $Force }
    }
}

Describe 'Show-OpPcView et Add-OpLogLine' -Skip:$script:noSta {
    BeforeAll { $script:ui = Import-OpMainWindow }
    AfterAll { $script:ui.Window.Close() }

    It 'remplit l''onglet et active l''installation' {
        $c = $script:ui.Controls
        Show-OpPcView -Controls $c -View (Get-TestView)
        $c.PcSystemTitle.Text | Should -Match '^PC-ATELIER'
        $c.PcChecks.Visibility | Should -Be 'Collapsed'
        $c.PcRebootBanner.Visibility | Should -Be 'Collapsed'
        @($c.PcSteps.ItemsSource).Count | Should -Be 4
        $c.PcOfficeText.Text | Should -Match 'aucun Office'
        $c.BtnInstallSelection.IsEnabled | Should -BeTrue
        $c.BtnAuto.IsEnabled | Should -BeTrue
    }

    It 'montre les contrôles et le bandeau de redémarrage, désactive l''installation sur un contrôle bloquant' {
        $checks = @(
            [pscustomobject]@{ Id = 'Elevation'; Label = 'Droits administrateur'; Result = 'Blocking'; Message = 'Session non élevée.' }
            [pscustomobject]@{ Id = 'PendingReboot'; Label = 'Redémarrage en attente'; Result = 'Warning'; Message = 'CBS' })
        $c = $script:ui.Controls
        Show-OpPcView -Controls $c -View (Get-TestView -Checks $checks)
        $c.PcChecks.Visibility | Should -Be 'Visible'
        $c.PcRebootBanner.Visibility | Should -Be 'Visible'
        $c.BtnInstallSelection.IsEnabled | Should -BeFalse
        $c.BtnAuto.IsEnabled | Should -BeFalse
    }

    It 'garde les 200 dernières lignes du journal' {
        foreach ($n in 1..205) { Add-OpLogLine -ListBox $script:ui.Controls.PcLastLog -Line "ligne $n" }
        $script:ui.Controls.PcLastLog.Items.Count | Should -Be 200
        $script:ui.Controls.PcLastLog.Items[0] | Should -Be 'ligne 6'
    }
}

Describe 'Reprise de la session interrompue' {
    It 'session automatique en cours : reprise proposée, sauf contrôle bloquant' {
        $view = Get-TestView
        $view | Add-Member -NotePropertyName Session -NotePropertyValue ([pscustomobject]@{ Mode = 'Auto'; Error = $null })
        (Get-OpPcSummary -View $view).CanResume | Should -BeTrue
        $view.Checks = @([pscustomobject]@{ Id = 'Elevation'; Label = 'Droits administrateur'; Result = 'Blocking'; Message = 'Session non élevée.' })
        (Get-OpPcSummary -View $view).CanResume | Should -BeFalse
    }

    It 'redémarrage en attente (redémarrage annulé) : bouton en attente, relance -Resume toujours possible' {
        $view = Get-TestView -Checks @([pscustomobject]@{ Id = 'PendingReboot'; Label = 'Redémarrage en attente'; Result = 'Warning'; Message = 'CBS' })
        $view | Add-Member -NotePropertyName Session -NotePropertyValue ([pscustomobject]@{ Mode = 'Auto'; Error = $null })
        $s = Get-OpPcSummary -View $view
        $s.CanResume | Should -BeFalse
        $s.ResumeAvailable | Should -BeTrue
    }

    It 'pas de reprise sans session, ni pour une session manuelle ; état illisible signalé' {
        (Get-OpPcSummary -View (Get-TestView)).CanResume | Should -BeFalse
        $view = Get-TestView
        $view | Add-Member -NotePropertyName Session -NotePropertyValue ([pscustomobject]@{ Mode = 'Manual'; Error = $null })
        (Get-OpPcSummary -View $view).CanResume | Should -BeFalse
        $view.Session = [pscustomobject]@{ Mode = $null; Error = 'État de session non reconnu' }
        $s = Get-OpPcSummary -View $view
        $s.CanResume | Should -BeFalse
        $s.Checks | Should -Contain 'Session interrompue : État de session non reconnu'
    }

    It 'fermeture : question seulement pendant une session automatique' {
        Get-OpPcCloseQuestion -Ui ([pscustomobject]@{}) | Should -BeNullOrEmpty
        Get-OpPcCloseQuestion -Ui ([pscustomobject]@{ AutoTask = [pscustomobject]@{ Done = $true } }) | Should -BeNullOrEmpty
        Get-OpPcCloseQuestion -Ui ([pscustomobject]@{ AutoTask = [pscustomobject]@{ Done = $false } }) | Should -Match 'état de la session est conservé'
    }
}

Describe 'Bouton « Reprendre la session interrompue »' -Skip:$script:noSta {
    BeforeAll { $script:ui2 = Import-OpMainWindow }
    AfterAll { $script:ui2.Window.Close() }

    It 'visible et actif seulement avec une session automatique à reprendre' {
        $c = $script:ui2.Controls
        Show-OpPcView -Controls $c -View (Get-TestView)
        $c.BtnResume.Visibility | Should -Be 'Collapsed'
        $view = Get-TestView
        $view | Add-Member -NotePropertyName Session -NotePropertyValue ([pscustomobject]@{ Mode = 'Auto'; Error = $null })
        Show-OpPcView -Controls $c -View $view
        $c.BtnResume.Visibility | Should -Be 'Visible'
        $c.BtnResume.IsEnabled | Should -BeTrue
        $c.BtnResume.ToolTip | Should -BeNullOrEmpty
        $view.Checks = @([pscustomobject]@{ Id = 'PendingReboot'; Label = 'Redémarrage en attente'; Result = 'Warning'; Message = 'CBS' })
        Show-OpPcView -Controls $c -View $view
        $c.BtnResume.Visibility | Should -Be 'Visible'
        $c.BtnResume.IsEnabled | Should -BeFalse
        $c.BtnResume.ToolTip | Should -Match 'Redémarrer d.abord'
    }
}
