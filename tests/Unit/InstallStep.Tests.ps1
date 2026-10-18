# Étapes en mode manuel (Invoke-OpInstallStep) et rapport de session (Write-OpInstallReport) : refus, choix de
# l'exécuteur, session de la CLI, rapport. Relevé, plan, exécuteurs et point de restauration simulés ; ProgramData
# redirigé vers TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpRoot', 'Get-OpPath', 'Get-OpConfiguration', 'Read-OpManifest', 'Get-OpNetworkConnection',
    'New-OpRestorePoint', 'Install-OpDefenderUpdate', 'Install-OpWindowsPackage', 'Install-OpOfficeUpdate', 'ConvertTo-OpReportHtml', 'Save-OpReport',
    'Get-OpSupportIdentity', 'Get-OpInitialSessionState', 'Read-OpSessionState', 'Save-OpSessionState', 'Complete-OpSessionState'
    foreach ($name in $private) { . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1") }
    foreach ($name in 'Get-OpSystemInfo', 'Test-OpPreflight', 'Get-OpInstallPlan', 'Invoke-OpInstallStep', 'Write-OpInstallReport') {
        . (Join-Path $repo "app\module\OffPatch\Public\$name.ps1")
    }

    function Get-Row([string]$Id, [string]$Category, [string]$State = 'Pending', [bool]$RebootAfter = $false) {
        [pscustomobject]@{ Sequence = 1; Id = $Id; Category = $Category; State = $State; Reason = "motif $Id"; Installed = $null; Available = '1'; RebootAfter = $RebootAfter }
    }
    function Get-Result([string]$Id, [string]$Category, [string]$State = 'UpToDate') {
        [pscustomobject]@{ Id = $Id; Category = $Category; State = $State; Reason = "fait $Id"; ExitCode = 0 }
    }
}

Describe 'Invoke-OpInstallStep et Write-OpInstallReport' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path $script:root | Out-Null
        Mock Write-OpLog {}
        Mock Get-OpPath { Join-Path $script:root 'programdata\temp' } -ParameterFilter { $Name -eq 'ClientTemp' }
        Mock Get-OpPath { Join-Path $script:root 'programdata\logs' } -ParameterFilter { $Name -eq 'ClientLogs' }
        Mock Get-OpPath { Join-Path $script:root 'programdata\state.json' } -ParameterFilter { $Name -eq 'State' }
        Mock Get-OpConfiguration { [pscustomobject]@{ Settings = [pscustomobject]@{}; OfficeSources = [pscustomobject]@{} } }
        Mock Get-OpSystemInfo {
            [pscustomobject]@{ ComputerName = 'PC-TEST'; SerialNumber = 'SN1'; Caption = 'Windows 11'; EditionId = 'Core'; DisplayVersion = '25H2'; CurrentBuild = '26200'; Ubr = 9457
                Office = [pscustomobject]@{ Products = @('O365HomePremRetail'); ChannelId = 'x'; Languages = @('fr-fr'); Version = [version]'16.0.1.1' } }
        }
        Mock Test-OpPreflight { [pscustomobject]@{ Label = 'Espace libre'; Result = 'Ok'; Message = 'ok' } }
        $script:plan = @(
            (Get-Row 'def' 'defender'), (Get-Row 'lcu' 'windows-lcu' -RebootAfter $true), (Get-Row 'off' 'office-source'), (Get-Row 'dot' 'dotnet' 'UpToDate'))
        Mock Get-OpInstallPlan { $script:plan }
        Mock Read-OpManifest { [pscustomobject]@{ generatedAt = '2026-10-14T09:12:00Z'; items = @($script:plan | ForEach-Object { [pscustomobject]@{ id = $_.Id; category = $_.Category } }) } }
        Mock New-OpRestorePoint { [pscustomobject]@{ Status = 'Created'; Description = 'OffPatch'; CreationTime = Get-Date; Reason = $null; ProtectionEnabled = $false } }
        Mock Install-OpDefenderUpdate { Get-Result $Item.id 'defender' }
        Mock Install-OpWindowsPackage { $r = Get-Result $Item.id 'windows-lcu'; $r | Add-Member RebootRequired $true; $r }
        Mock Install-OpOfficeUpdate { Get-Result $Item.id 'office-source' 'Error' }
        Mock Get-OpNetworkConnection { }
    }

    It 'choisit l''exécuteur de la catégorie et complète le résultat' -TestCases @(
        @{ Id = 'def'; Executor = 'Install-OpDefenderUpdate'; Reboot = $false }
        @{ Id = 'lcu'; Executor = 'Install-OpWindowsPackage'; Reboot = $true }
        @{ Id = 'off'; Executor = 'Install-OpOfficeUpdate'; Reboot = $false }
    ) {
        param($Id, $Executor, $Reboot)
        $r = Invoke-OpInstallStep -StepId $Id -Root $script:root
        $r.Id | Should -Be $Id
        $r.RebootAfter | Should -Be $Reboot
        $r.Seconds | Should -BeGreaterOrEqual 0
        Should -Invoke $Executor -Times 1 -Exactly
    }

    It 'refuse <Cas> sans lancer d''exécuteur' -TestCases @(
        @{ Cas = 'une étape qui n''est pas à installer'; Id = 'dot'; Blocking = $false; Pattern = '*état UpToDate*' }
        @{ Cas = 'une étape absente du plan'; Id = 'inconnue'; Blocking = $false; Pattern = '*absente du plan*' }
        @{ Cas = 'tout, sur un contrôle préalable bloquant'; Id = 'def'; Blocking = $true; Pattern = '*bloquant*Espace libre*' }
    ) {
        param($Cas, $Id, $Blocking, $Pattern)
        if ($Blocking) { Mock Test-OpPreflight { [pscustomobject]@{ Label = 'Espace libre'; Result = 'Blocking'; Message = '3 Go' } } }
        $script:stepId = $Id
        { Invoke-OpInstallStep -StepId $script:stepId -Root $script:root } | Should -Throw $Pattern -Because $Cas
        Should -Invoke Install-OpDefenderUpdate -Times 0 -Exactly
        Should -Invoke New-OpRestorePoint -Times 0 -Exactly
    }

    It 'crée le point de restauration une seule fois et garde chaque résultat dans la session' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        Invoke-OpInstallStep -StepId 'lcu' -Root $script:root | Out-Null
        Should -Invoke New-OpRestorePoint -Times 1 -Exactly
        $session = Get-Content -LiteralPath (Join-Path $script:root 'programdata\state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($session.steps.Id) | Should -Be @('def', 'lcu')
        $session.before.ComputerName | Should -Be 'PC-TEST'
        $session.before.Office.Version | Should -Be '16.0.1.1'
        $session.restorePoint.Status | Should -Be 'Created'
        $session.sessionId | Should -Match '^[0-9a-f-]{36}$'
        $session.rebootCount | Should -Be 0
        $session.support.relativeRoot | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:root 'programdata\state.json.tmp') | Should -BeFalse
    }

    It 'respecte -WhatIf' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Install-OpDefenderUpdate -Times 0 -Exactly
        Test-Path (Join-Path $script:root 'programdata\state.json') | Should -BeFalse
    }

    It 'écrit le rapport avec les étapes exécutées et le reste du plan, puis clôt la session' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        $path = Write-OpInstallReport -Root $script:root
        Split-Path -Leaf $path | Should -Match '^\d{4}-\d{2}-\d{2}_PC-TEST_SN1\.html$'
        $html = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $html | Should -Match 'fait def'
        $html | Should -Match 'motif lcu'
        $html | Should -Not -Match 'motif def'
        $html | Should -Match 'mode Avion'
        $html | Should -Match 'Point créé par OffPatch'
        Test-Path (Join-Path $script:root 'programdata\state.json') | Should -BeFalse
        @(Get-ChildItem -Path (Join-Path $script:root 'programdata\logs') -Filter 'state_*.json').Count | Should -Be 1
    }

    It 'écrit un rapport sans session en cours (aucune étape exécutée)' {
        Mock Get-OpNetworkConnection { [pscustomobject]@{ Name = 'Réseau'; Connectivity = 'Internet' } }
        $path = Write-OpInstallReport -Root $script:root
        $html = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $html | Should -Match 'motif def'
        $html | Should -Not -Match 'mode Avion'
        $html | Should -Match 'Aucune étape exécutée : aucun point demandé'
    }

    It 'reprend les avertissements et erreurs des journaux de chaque appel (étapes et rapport)' {
        $stepLog = Join-Path $script:root 'session_etape.log'
        $reportLog = Join-Path $script:root 'session_rapport.log'
        Set-Content -LiteralPath $stepLog -Value '2026-10-17 10:00:00 [WARN] avertissement de l''étape' -Encoding UTF8
        Set-Content -LiteralPath $reportLog -Value '2026-10-17 11:00:00 [ERROR] erreur du rapport' -Encoding UTF8
        $script:OpLog = [pscustomobject]@{ Path = $stepLog }
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        $script:OpLog = [pscustomobject]@{ Path = $reportLog }
        $html = Get-Content -LiteralPath (Write-OpInstallReport -Root $script:root) -Raw -Encoding UTF8
        $script:OpLog = $null
        $html | Should -Match 'avertissement de l&#39;étape'
        $html | Should -Match 'erreur du rapport'
    }
}
