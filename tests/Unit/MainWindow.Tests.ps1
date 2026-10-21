# Fenêtre principale (cahier des charges 9) : XAML chargé par XamlReader, sans affichage. Thread STA requis
# (powershell.exe l'est par défaut) ; sinon les tests de chargement sont ignorés.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:xamlPath = Join-Path $repo 'app\gui\MainWindow.xaml'
    . (Join-Path $repo 'app\gui\MainWindow.ps1')
}

Describe 'MainWindow.xaml' {
    It 'est un XML valide, sans x:Class ni gestionnaire d''événement (XamlReader les refuse)' {
        [xml]$xml = Get-Content -LiteralPath $script:xamlPath -Raw -Encoding UTF8
        $xml.Window | Should -Not -BeNullOrEmpty
        $text = Get-Content -LiteralPath $script:xamlPath -Raw -Encoding UTF8
        $text | Should -Not -Match 'x:Class'
        $text | Should -Not -Match '\s(Click|Loaded|Closing|Checked|SelectionChanged)='
    }
}

Describe 'Import-OpMainWindow' -Skip:$script:noSta {
    BeforeAll { $script:ui = Import-OpMainWindow -Path $script:xamlPath }
    AfterAll { if ($script:ui) { $script:ui.Window.Close() } }

    It 'charge une fenêtre redimensionnable, titrée OffPatch' {
        $script:ui.Window | Should -BeOfType [System.Windows.Window]
        $script:ui.Window.Title | Should -Be 'OffPatch'
        $script:ui.Window.ResizeMode | Should -Be 'CanResize'
    }

    It 'a les trois onglets du cahier des charges, libellés en français' {
        @($script:ui.Controls.MainTabs.Items | ForEach-Object { $_.Header }) | Should -Be @('Ce PC', 'Dépôt', 'Journal')
    }

    It 'retrouve chaque élément nommé (<_>)' -ForEach @('Header', 'HeaderTitle', 'HeaderVersion', 'HeaderDepotDate', 'HeaderAlert', 'HeaderAlertText', 'MainTabs', 'TabPc', 'TabDepot', 'TabLog', 'PcRoot', 'DepotRoot', 'LogRoot') {
        $script:ui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'masque l''alerte de fraîcheur par défaut' {
        $script:ui.Controls.HeaderAlert.Visibility | Should -Be 'Collapsed'
    }

    It 'lève une erreur sur un XAML absent' {
        { Import-OpMainWindow -Path (Join-Path $TestDrive 'absent.xaml') } | Should -Throw
    }
}
