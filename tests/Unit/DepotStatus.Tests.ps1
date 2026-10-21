# État du dépôt (cahier des charges 8.2, 9) et en-tête de la fenêtre. Manifeste simulé ; l'en-tête est rempli sur
# une vraie fenêtre chargée sans affichage (thread STA requis, sinon ces tests sont ignorés).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpManifest', 'Get-OpConfiguration') { . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1") }
    . (Join-Path $repo 'app\module\OffPatch\Public\Get-OpDepotStatus.ps1')
    . (Join-Path $repo 'app\gui\MainWindow.ps1')
    . (Join-Path $repo 'app\gui\Header.ps1')
    $script:now = [datetime]'2026-10-21T12:00:00Z'
    function Get-TestStatus([string]$GeneratedAt, [object[]]$Items = @([pscustomobject]@{ id = 'x' })) {
        $script:testManifest = [pscustomobject]@{ schemaVersion = 1; generatedAt = $GeneratedAt; items = $Items }
        Mock Read-OpManifest { $script:testManifest }
        Get-OpDepotStatus -Root $repo -StaleDays 35 -Now $script:now
    }
}

Describe 'Get-OpDepotStatus' {
    It 'dépôt récent : Ok, âge en jours entiers, date locale' {
        $s = Get-TestStatus '2026-10-18T07:40:58Z'
        $s.State | Should -Be 'Ok'
        $s.AgeDays | Should -Be 3
        $s.ItemCount | Should -Be 1
        $s.GeneratedAt | Should -Be ([datetime]'2026-10-18T07:40:58Z')
        $s.StaleDays | Should -Be 35
    }

    It 'au-delà du seuil : Stale' {
        (Get-TestStatus '2026-09-01T00:00:00Z').State | Should -Be 'Stale'
        (Get-TestStatus '2026-09-16T00:00:00Z').State | Should -Be 'Ok' -Because '35 jours tout juste'
    }

    It 'dépôt vide ou sans date : Empty' {
        (Get-TestStatus $null @()).State | Should -Be 'Empty'
        (Get-TestStatus '2026-10-18T07:40:58Z' @()).State | Should -Be 'Empty'
    }

    It 'manifeste illisible : Unreadable avec le motif' {
        Mock Read-OpManifest { throw 'JSON invalide' }
        $s = Get-OpDepotStatus -Root $repo -StaleDays 35 -Now $script:now
        $s.State | Should -Be 'Unreadable'
        $s.Error | Should -Be 'JSON invalide'
    }

    It 'prend le seuil dans settings.json par défaut' {
        Mock Get-OpConfiguration { [pscustomobject]@{ Settings = [pscustomobject]@{ client = [pscustomobject]@{ staleDepotWarningDays = 2 } } } }
        $script:testManifest = [pscustomobject]@{ schemaVersion = 1; generatedAt = '2026-10-18T07:40:58Z'; items = @([pscustomobject]@{ id = 'x' }) }
        Mock Read-OpManifest { $script:testManifest }
        (Get-OpDepotStatus -Root $repo -Now $script:now).State | Should -Be 'Stale'
    }
}

Describe 'Show-OpHeader' -Skip:$script:noSta {
    BeforeAll { $script:ui = Import-OpMainWindow }
    AfterAll { $script:ui.Window.Close() }

    It 'affiche la version et la date, sans alerte pour un dépôt récent' {
        $s = Get-TestStatus '2026-10-18T07:40:58Z'
        $s.ToolVersion = '0.1.0'
        Show-OpHeader -Controls $script:ui.Controls -Status $s
        $script:ui.Controls.HeaderVersion.Text | Should -Be 'version 0.1.0'
        $script:ui.Controls.HeaderDepotDate.Text | Should -Be ('Dépôt du {0:dd/MM/yyyy} (il y a 3 jours)' -f ([datetime]'2026-10-18T07:40:58Z'))
        $script:ui.Controls.HeaderAlert.Visibility | Should -Be 'Collapsed'
    }

    It 'affiche l''alerte pour <Cas>, et la retire ensuite' -TestCases @(
        @{ Cas = 'un dépôt ancien'; GeneratedAt = '2026-09-01T00:00:00Z'; Items = @([pscustomobject]@{ id = 'x' }); Alert = 'plus de 35 jours'; Date = '^Dépôt du ' }
        @{ Cas = 'un dépôt vide'; GeneratedAt = $null; Items = @(); Alert = 'Aucune mise à jour'; Date = '^Dépôt vide$' }
    ) {
        param($GeneratedAt, $Items, $Alert, $Date)
        Show-OpHeader -Controls $script:ui.Controls -Status (Get-TestStatus $GeneratedAt $Items)
        $script:ui.Controls.HeaderAlert.Visibility | Should -Be 'Visible'
        $script:ui.Controls.HeaderAlertText.Text | Should -Match $Alert
        $script:ui.Controls.HeaderDepotDate.Text | Should -Match $Date
        Show-OpHeader -Controls $script:ui.Controls -Status (Get-TestStatus '2026-10-21T08:00:00Z')
        $script:ui.Controls.HeaderAlert.Visibility | Should -Be 'Collapsed'
        $script:ui.Controls.HeaderDepotDate.Text | Should -Match '\(aujourd''hui\)$'
    }

    It 'met le motif en infobulle pour un manifeste illisible' {
        Mock Read-OpManifest { throw 'JSON invalide' }
        Show-OpHeader -Controls $script:ui.Controls -Status (Get-OpDepotStatus -Root $repo -StaleDays 35 -Now $script:now)
        $script:ui.Controls.HeaderAlertText.Text | Should -Match 'illisible'
        $script:ui.Controls.HeaderAlert.ToolTip | Should -Be 'JSON invalide'
    }
}
