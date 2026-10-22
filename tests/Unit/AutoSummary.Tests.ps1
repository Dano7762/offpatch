# Récapitulatif du mode automatique (cahier des charges 8.6) : textes, fenêtre réelle chargée sans affichage (thread
# STA requis, sinon ces tests sont ignorés), script du runspace de la session (Invoke-OpAutoSession simulé). Rien
# n'est installé ni redémarré.
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
    foreach ($name in 'MainWindow', 'Background', 'PcTab', 'Dialogs\AutoSummary') { . (Join-Path $repo "app\gui\$name.ps1") }

    function Get-TestRow([string]$Id, [string]$Category, [string]$Label, [string]$State = 'Pending', [bool]$RebootAfter = $false) {
        [pscustomobject]@{ Sequence = 1; Id = $Id; Category = $Category; CategoryLabel = $Label; State = $State; StateLabel = $State; Reason = "motif $Id"; Available = $null; RebootAfter = $RebootAfter }
    }
    function Get-TestView([hashtable]$Info = @{}, [object[]]$Checks = @()) {
        $i = [ordered]@{
            ComputerName = 'PC-ATELIER'; Caption = 'Microsoft Windows 10 Professionnel'; DisplayVersion = '22H2'; CurrentBuild = 19045; Ubr = 6000
            Architecture = 'x64'; Family = 'Windows10'; Manufacturer = 'Fabricant'; Model = 'Modèle 14'; SerialNumber = 'SN1'
            SystemDrive = 'C:'; FreeSpaceBytes = [long]60GB; Power = [pscustomobject]@{ OnBattery = $false; BatteryPercent = $null }
            Esu = $null; Office = $null
        }
        foreach ($k in $Info.Keys) { $i[$k] = $Info[$k] }
        $plan = @((Get-TestRow 'def' 'defender' 'Définitions Defender'), (Get-TestRow 'lcu' 'windows-lcu' 'Cumulative Windows' -RebootAfter $true),
            (Get-TestRow 'net' 'dotnet' '.NET Framework'), (Get-TestRow 'ssu' 'windows-ssu' 'Pile de maintenance' 'UpToDate'),
            [pscustomobject]@{ Sequence = 5; Id = $null; Category = 'office-source'; CategoryLabel = 'Office'; State = 'NotApplicable'; StateLabel = 'Non applicable'; Reason = 'Aucun Office Click-to-Run.'; Available = $null; RebootAfter = $false })
        [pscustomobject]@{ Info = [pscustomobject]$i; Checks = $Checks; Plan = $plan; OfficeSources = $null }
    }
    $script:esu = [pscustomobject]@{ Id = 'Esu'; Label = 'ESU Windows 10'; Result = 'Warning'; Message = 'ESU absent ou indétectable.'; Action = 'SkipWindowsInAuto' }
    $script:network = [pscustomobject]@{ Id = 'Network'; Label = 'Réseau'; Result = 'Warning'; Message = 'PC connecté : activer le mode Avion pendant la session.'; Action = $null }
    $script:battery = [pscustomobject]@{ Id = 'Battery'; Label = 'Alimentation'; Result = 'Warning'; Message = 'Portable sur batterie : brancher le secteur avant le mode auto.'; Action = 'ConfirmAutoMode' }
    $script:ok = [pscustomobject]@{ Id = 'FreeSpace'; Label = 'Espace libre'; Result = 'Ok'; Message = 'ok'; Action = $null }
}

Describe 'Get-OpAutoSummary' {
    It 'étapes à installer dans l''ordre, redémarrage signalé, Office, rien à forcer' {
        $s = Get-OpAutoSummary -View (Get-TestView -Checks @($script:ok))
        $s.Steps | Should -Be @('Définitions Defender : def', 'Cumulative Windows : lcu — redémarrage ensuite', '.NET Framework : net')
        $s.Office | Should -Match 'aucun Office Click-to-Run'
        $s.Warnings.Count | Should -Be 0
        $s.CanForceWindows | Should -BeFalse
        $s.CanStart | Should -BeTrue
    }

    It 'Windows 10 sans ESU : forçage proposé, étapes Windows et .NET marquées ; mode Avion et batterie rappelés' {
        $s = Get-OpAutoSummary -View (Get-TestView -Checks @($script:esu, $script:network, $script:battery, $script:ok))
        $s.CanForceWindows | Should -BeTrue
        $s.Steps[0] | Should -Be 'Définitions Defender : def'
        $s.Steps[1] | Should -Match 'redémarrage ensuite — ignorée sauf forçage'
        $s.Steps[2] | Should -Match 'ignorée sauf forçage'
        $s.Warnings | Should -Be @('ESU Windows 10 : ESU absent ou indétectable.', 'Réseau : PC connecté : activer le mode Avion pendant la session.', 'Alimentation : Portable sur batterie : brancher le secteur avant le mode auto.')
    }

    It 'contrôle bloquant : démarrage impossible' {
        $blocking = [pscustomobject]@{ Id = 'Elevation'; Label = 'Droits administrateur'; Result = 'Blocking'; Message = 'Session non élevée.'; Action = $null }
        (Get-OpAutoSummary -View (Get-TestView -Checks @($blocking))).CanStart | Should -BeFalse
    }
}

Describe 'Import-OpAutoSummaryWindow' -Skip:$script:noSta {
    It 'remplit la fenêtre : étapes, avertissements, case de forçage décochée' {
        $d = Import-OpAutoSummaryWindow -View (Get-TestView -Checks @($script:esu, $script:network))
        try {
            $c = $d.Controls
            $c.SummarySteps.Items.Count | Should -Be 3
            $c.SummaryWarnings.Visibility | Should -Be 'Visible'
            $c.SummaryWarningsText.Text | Should -Match 'mode Avion'
            $c.SummaryForceWindows.Visibility | Should -Be 'Visible'
            $c.SummaryForceWindows.IsChecked | Should -BeFalse
            $c.BtnSummaryStart.IsEnabled | Should -BeTrue
        } finally { $d.Window.Close() }
    }

    It 'sans avertissement ni ESU manquant : ni bandeau ni case de forçage' {
        $d = Import-OpAutoSummaryWindow -View (Get-TestView -Checks @($script:ok))
        try {
            $d.Controls.SummaryWarnings.Visibility | Should -Be 'Collapsed'
            $d.Controls.SummaryForceWindows.Visibility | Should -Be 'Collapsed'
        } finally { $d.Window.Close() }
    }
}

Describe 'Session automatique (script du runspace)' {
    BeforeAll {
        function Initialize-OpSession { param($Kind, $Queue, $Root) }
        function Invoke-OpAutoSession { [CmdletBinding(SupportsShouldProcess)] param($Root, [switch]$ForceWindows, $OnStep, $OnTick, $IsCancelled) }
    }
    BeforeEach {
        $OpQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $source = New-Object System.Threading.CancellationTokenSource
        $OpCancel = $source.Token
        Mock Initialize-OpSession {}
        Mock Invoke-OpAutoSession {
            & $OnStep ([pscustomobject]@{ Id = 'lcu'; Category = 'windows-lcu'; State = 'Pending' })
            & $OnStep ([pscustomobject]@{ Id = 'lcu'; State = 'UpToDate'; Seconds = 3.0 })
            & $OnTick 2
            [pscustomobject]@{ Result = 'Cancelled'; Cancelled = (& $IsCancelled) }
        }
    }

    It 'transmet le forçage sans confirmation, dépose étapes et compte à rebours, annulation par le jeton' {
        $source.Cancel()
        $r = & $script:OpPcAutoScript -Root 'X:\' -ForceWindows $true
        $r.Cancelled | Should -BeTrue
        Should -Invoke Invoke-OpAutoSession -Times 1 -Exactly -ParameterFilter { $ForceWindows -and $Root -eq 'X:\' }
        $all = @(); $m = $null; while ($OpQueue.TryDequeue([ref]$m)) { $all += $m }
        @($all | ForEach-Object { "$($_.Kind) $(if ($_.Kind -eq 'AutoStep') { "$($_.Id) $($_.Done)" } else { $_.Seconds })" }) | Should -Be @('AutoStep lcu False', 'AutoStep lcu True', 'Countdown 2')
    }

    It 'sans annulation, le jeton n''arrête rien' {
        (& $script:OpPcAutoScript -Root 'X:\' -ForceWindows $false).Cancelled | Should -BeFalse
        Should -Invoke Invoke-OpAutoSession -Times 1 -Exactly -ParameterFilter { -not $ForceWindows }
    }
}
