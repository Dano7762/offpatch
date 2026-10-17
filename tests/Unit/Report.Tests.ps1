# Rapport d'intervention (cahier des charges 8.8) : contenu, échappement, nom du fichier, copie dans ProgramData.
# Sans effet sur le système : ProgramData redirigé vers TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpRoot', 'Get-OpPath', 'ConvertTo-OpReportHtml', 'Save-OpReport') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    $script:configuration = [pscustomobject]@{ OfficeSources = (Get-Content -LiteralPath (Join-Path $repo 'config\office\sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json) }

    function Get-Info([int]$Ubr, $Office = $null) {
        [pscustomobject]@{
            ComputerName = 'PC-ATELIER'; Manufacturer = 'Fabricant'; Model = 'Modèle 14'; SerialNumber = 'SN 12/34'
            Caption = 'Windows 11 Famille'; EditionId = 'Core'; DisplayVersion = '25H2'; CurrentBuild = '26200'; Ubr = $Ubr; Esu = $null; Office = $Office
        }
    }
    function Get-Session([hashtable]$Extra = @{}) {
        $log = Join-Path $TestDrive "session-$([guid]::NewGuid()).log"
        Set-Content -Path $log -Encoding UTF8 -Value @(
            '2026-10-17 09:00:00 [INFO] début'
            '2026-10-17 09:01:00 [WARN] Defender lent à revenir'
            '2026-10-17 09:02:00 [ERROR] DISM a échoué, code 3 (0x00000003).')
        $office = [pscustomobject]@{ Products = @('HomeStudent2019Retail'); ChannelId = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'; Languages = @('fr-fr'); Version = '16.0.19127.20800' }
        $s = [ordered]@{
            StartTime = [datetime]'2026-10-17 09:00:00'; EndTime = [datetime]'2026-10-17 10:15:00'
            Before = Get-Info 9457 $office; After = Get-Info 9550 $office
            Steps = @(
                [pscustomobject]@{ Id = 'win11-x64-defender-platform-4.18.26080.4'; Category = 'defender-platform'; State = 'UpToDate'; Reason = 'ok'; Installed = '4.18.26080.4'; ExitCode = 0; Seconds = 27.4 }
                [pscustomobject]@{ Id = 'win11-x64-defender-1.459.553.0'; Category = 'defender'; State = 'UpToDate'; Reason = 'ok'; Installed = '1.459.553.0'; ExitCode = 0; Seconds = 16 }
                [pscustomobject]@{ Id = 'win11-x64-lcu-<test>'; Category = 'windows-lcu'; State = 'Error'; Reason = 'DISM a échoué, code 3 (0x00000003).'; ExitCode = 3; Seconds = 2 }
                [pscustomobject]@{ Id = $null; Category = 'office-source'; State = 'NotApplicable'; Reason = 'Office 2016/2019 : fin de support Microsoft (octobre 2025)' })
            LogPath = $log; Offline = $true
            RestorePoint = [pscustomobject]@{ Status = 'Created'; Description = 'OffPatch avant mises à jour'; CreationTime = [datetime]'2026-10-17 09:00:30'; ProtectionEnabled = $true }
            ToolVersion = '0.1.0'; DepotDate = '2026-10-14T09:12:00Z'
        }
        foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }
        [pscustomobject]$s
    }
}

Describe 'ConvertTo-OpReportHtml' {
    BeforeAll { $script:html = ConvertTo-OpReportHtml -Session (Get-Session) -Configuration $script:configuration }

    It 'produit un document HTML autonome, sans ressource externe' {
        $script:html | Should -Match '^<!DOCTYPE html>'
        $script:html | Should -Match '@media print'
        $script:html | Should -Not -Match '<script|<link|src='
    }

    It 'contient <Cas>' -TestCases @(
        @{ Cas = 'les heures de début et de fin'; Pattern = '17/10/2026 09:00:00.*17/10/2026 10:15:00' }
        @{ Cas = 'le poste et son numéro de série'; Pattern = 'PC-ATELIER.*Fabricant.*Modèle 14.*SN 12/34' }
        @{ Cas = 'Windows avant et après'; Pattern = 'build 26200\.9457.*build 26200\.9550' }
        @{ Cas = 'les versions Defender et le rappel'; Pattern = 'Version 4\.18\.26080\.4.*Version 1\.459\.553\.0.*se met à jour seul' }
        @{ Cas = 'le motif Office et la recommandation'; Pattern = 'fin de support Microsoft.*Passer à une version' }
        @{ Cas = 'les étapes avec code retour et durée'; Pattern = '<td>Erreur</td><td>3</td><td>2 s</td>' }
        @{ Cas = 'les erreurs et avertissements du journal'; Pattern = 'Defender lent.*DISM a échoué' }
        @{ Cas = 'le rappel hors ligne'; Pattern = 'mode Avion' }
        @{ Cas = 'le point de restauration et la remarque'; Pattern = 'OffPatch avant mises à jour.*Checkpoint-Computer, à vérifier' }
        @{ Cas = 'la version de l''outil et la date du dépôt'; Pattern = '0\.1\.0.*2026-10-14' }
    ) {
        param($Cas, $Pattern)
        ($script:html -replace '\r?\n', ' ') | Should -Match $Pattern -Because $Cas
    }

    It 'échappe les valeurs' {
        $script:html | Should -Match 'win11-x64-lcu-&lt;test&gt;'
        $script:html | Should -Not -Match '<test>'
    }

    It 'tolère une session minimale (abandon, sans relevé de fin ni point de restauration)' {
        $minimal = [pscustomobject]@{ StartTime = Get-Date; Abandoned = $true; Before = Get-Info 9457 }
        $h = ConvertTo-OpReportHtml -Session $minimal
        $h | Should -Match 'Session interrompue'
        $h | Should -Match 'Aucun\.'
        $h | Should -Not -Match 'mode Avion'
    }
}

Describe 'Save-OpReport' {
    BeforeEach {
        Mock Write-OpLog {}
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:clientLogs = Join-Path $script:root 'programdata-logs'
        Mock Get-OpPath { $script:clientLogs } -ParameterFilter { $Name -eq 'ClientLogs' }
    }

    It 'écrit rapports\AAAA-MM-JJ_NomPC_NumeroDeSerie.html et sa copie, en UTF-8' {
        $path = Save-OpReport -Session (Get-Session) -Root $script:root
        Split-Path -Leaf $path | Should -Be '2026-10-17_PC-ATELIER_SN_12_34.html'
        Split-Path -Parent $path | Should -Be (Join-Path $script:root 'rapports')
        Get-Content -LiteralPath $path -Raw -Encoding UTF8 | Should -Match 'Modèle 14'
        Test-Path (Join-Path $script:clientLogs '2026-10-17_PC-ATELIER_SN_12_34.html') | Should -BeTrue
        @(Get-ChildItem -Path (Split-Path -Parent $path) -Filter '*.tmp').Count | Should -Be 0
    }

    It 'garde le rapport du support si la copie dans ProgramData échoue' {
        Mock Get-OpPath { 'Z:\inexistant\?' } -ParameterFilter { $Name -eq 'ClientLogs' }
        $path = Save-OpReport -Session (Get-Session) -Root $script:root
        Test-Path $path | Should -BeTrue
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' }
    }

    It 'respecte -WhatIf' {
        Save-OpReport -Session (Get-Session) -Root $script:root -WhatIf | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:root 'rapports') | Should -BeFalse
    }
}
