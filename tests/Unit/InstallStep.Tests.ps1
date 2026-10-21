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
    'Get-OpSupportIdentity', 'Get-OpInitialSessionState', 'Read-OpSessionState', 'Save-OpSessionState', 'Complete-OpSessionState', 'Unregister-OpResumeTask',
    'Get-OpPendingReboot', 'Suspend-OpSystemSleep', 'Resume-OpSystemSleep'
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
        Mock Get-OpPath { Join-Path $script:root 'programdata\resume.ps1' } -ParameterFilter { $Name -eq 'ClientResume' }
        Mock Unregister-OpResumeTask { $true }
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
        Mock Get-OpPendingReboot { }
        Mock Suspend-OpSystemSleep { [uint32]2147483648 }
        Mock Resume-OpSystemSleep {}
    }

    It 'suspend la mise en veille pendant l''exécuteur et la rétablit, même en cas d''exception' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        Should -Invoke Suspend-OpSystemSleep -Times 1 -Exactly
        Should -Invoke Resume-OpSystemSleep -Times 1 -Exactly -ParameterFilter { $PreviousState -eq 2147483648 }
        Mock Install-OpWindowsPackage { throw 'DISM introuvable' }
        { Invoke-OpInstallStep -StepId 'lcu' -Root $script:root } | Should -Throw '*DISM introuvable*'
        Should -Invoke Resume-OpSystemSleep -Times 2 -Exactly
    }

    It 'rappelle le redémarrage en attente en fin de session, à l''écran et dans le rapport' {
        Mock Get-OpPendingReboot { 'CBS' }
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        $path = Write-OpInstallReport -Root $script:root -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -Match 'Redémarrage nécessaire.*CBS'
        Get-Content -LiteralPath $path -Raw -Encoding UTF8 | Should -Match 'Redémarrage nécessaire pour terminer'
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

    It 'abandonne une étape au deuxième échec et refuse toute nouvelle tentative (8.6)' {
        $first = Invoke-OpInstallStep -StepId 'off' -Root $script:root
        $first.Failures | Should -Be 1
        $first.Abandoned | Should -BeFalse
        $second = Invoke-OpInstallStep -StepId 'off' -Root $script:root
        $second.Failures | Should -Be 2
        $second.Abandoned | Should -BeTrue
        $second.Reason | Should -Match 'abandonnée après deux échecs'
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -match 'off' } -Times 1 -Exactly
        { Invoke-OpInstallStep -StepId 'off' -Root $script:root } | Should -Throw '*abandonnée après deux échecs*'
        Should -Invoke Install-OpOfficeUpdate -Times 2 -Exactly
        $session = Get-Content -LiteralPath (Join-Path $script:root 'programdata\state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        @($session.steps).Count | Should -Be 1
        $session.steps[0].Abandoned | Should -BeTrue
        # Les autres étapes restent possibles.
        (Invoke-OpInstallStep -StepId 'def' -Root $script:root).State | Should -Be 'UpToDate'
    }

    It 'ne compte pas une réussite comme un échec' {
        (Invoke-OpInstallStep -StepId 'def' -Root $script:root).Failures | Should -Be 0
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

    It 'supprime en fin de session la tâche, resume.ps1 et temp, et rappelle le mode Avion à l''écran' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $script:root 'programdata\temp\sous') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:root 'programdata\temp\sous\a.xml') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:root 'programdata\resume.ps1') -Value 'x'
        $path = Write-OpInstallReport -Root $script:root -WarningVariable warnings -WarningAction SilentlyContinue
        $path | Should -Not -BeNullOrEmpty
        Should -Invoke Unregister-OpResumeTask -Times 1 -Exactly
        Test-Path (Join-Path $script:root 'programdata\temp') | Should -BeFalse
        Test-Path (Join-Path $script:root 'programdata\resume.ps1') | Should -BeFalse
        @(Get-ChildItem -Path (Join-Path $script:root 'programdata\logs') -Filter 'state_*.json').Count | Should -Be 1
        "$warnings" | Should -Match 'mode Avion'
    }

    It 'termine la session même si la tâche ne peut être supprimée, sans rappel si le PC est en ligne' {
        Mock Unregister-OpResumeTask { throw 'accès refusé' }
        Mock Get-OpNetworkConnection { [pscustomobject]@{ Name = 'Réseau'; Connectivity = 'Internet' } }
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        Set-Content -LiteralPath (Join-Path $script:root 'programdata\resume.ps1') -Value 'x'
        $path = Write-OpInstallReport -Root $script:root -WarningVariable warnings
        $path | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:root 'programdata\resume.ps1') | Should -BeFalse
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*accès refusé*' }
        @($warnings).Count | Should -Be 0
    }

    It 'ne supprime rien avec -WhatIf' {
        Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null
        Set-Content -LiteralPath (Join-Path $script:root 'programdata\resume.ps1') -Value 'x'
        Write-OpInstallReport -Root $script:root -WhatIf -WarningAction SilentlyContinue | Out-Null
        Test-Path (Join-Path $script:root 'programdata\resume.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:root 'programdata\state.json') | Should -BeTrue
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
