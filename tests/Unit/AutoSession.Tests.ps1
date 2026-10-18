# Session automatique de bout en bout (cahier des charges 8.6) : étapes, redémarrage avec tâche de reprise, étapes
# après la reprise, limite de redémarrages, rapport et nettoyage de fin de session. Fonctions réelles du module ;
# seules les frontières avec le système sont simulées : relevé et plan, exécuteurs, point de restauration, CIM,
# planificateur de tâches et Restart-Computer. ProgramData redirigé vers TestDrive : rien ne redémarre.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpRoot', 'Get-OpPath', 'Get-OpConfiguration', 'Read-OpManifest', 'Get-OpNetworkConnection',
    'New-OpRestorePoint', 'Install-OpDefenderUpdate', 'Install-OpWindowsPackage', 'Install-OpOfficeUpdate', 'ConvertTo-OpReportHtml', 'Save-OpReport',
    'Get-OpSupportIdentity', 'Get-OpInitialSessionState', 'Read-OpSessionState', 'Save-OpSessionState', 'Complete-OpSessionState',
    'Register-OpResumeTask', 'Unregister-OpResumeTask'
    foreach ($name in $private) { . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1") }
    foreach ($name in 'Get-OpSystemInfo', 'Test-OpPreflight', 'Get-OpInstallPlan', 'Invoke-OpInstallStep', 'Restart-OpSession', 'Write-OpInstallReport', 'Invoke-OpAutoSession') {
        . (Join-Path $repo "app\module\OffPatch\Public\$name.ps1")
    }

    function Get-Row([string]$Id, [string]$Category, [bool]$RebootAfter = $false) {
        [pscustomobject]@{ Sequence = 1; Id = $Id; Category = $Category; State = 'Pending'; Reason = "motif $Id"; Installed = $null; Available = '1'; RebootAfter = $RebootAfter }
    }
    function Get-Result([string]$Id, [string]$Category) {
        $script:installed[$Id] = $true
        [pscustomobject]@{ Id = $Id; Category = $Category; State = 'UpToDate'; Reason = "fait $Id"; ExitCode = 0 }
    }
    function Get-ProgramData([string]$Child) { Join-Path (Join-Path $script:root 'programdata') $Child }
}

Describe 'Session automatique simulée de bout en bout' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path (Join-Path $script:root 'app') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:root 'app\resume.ps1') -Value '# amorce' -Encoding UTF8
        Mock Write-OpLog {}
        Mock Start-Sleep {}
        Mock Restart-Computer {}
        Mock Get-OpPath { Get-ProgramData 'state.json' } -ParameterFilter { $Name -eq 'State' }
        Mock Get-OpPath { Get-ProgramData 'logs' } -ParameterFilter { $Name -eq 'ClientLogs' }
        Mock Get-OpPath { Get-ProgramData 'temp' } -ParameterFilter { $Name -eq 'ClientTemp' }
        Mock Get-OpPath { Get-ProgramData 'resume.ps1' } -ParameterFilter { $Name -eq 'ClientResume' }
        $script:maxReboots = 3
        Mock Get-OpConfiguration {
            [pscustomobject]@{ Settings = [pscustomobject]@{ client = [pscustomobject]@{ maxAutoReboots = $script:maxReboots; rebootCountdownSeconds = 3 } }; OfficeSources = [pscustomobject]@{} }
        }
        Mock Get-CimInstance { [pscustomobject]@{ VolumeSerialNumber = 'D29F1400'; UserName = 'PC\utilisateur' } }
        Mock Get-OpSystemInfo {
            [pscustomobject]@{ ComputerName = 'PC-AUTO'; SerialNumber = 'SN9'; Caption = 'Windows 11'; EditionId = 'Core'; DisplayVersion = '25H2'; CurrentBuild = '26200'; Ubr = 9457; Office = $null }
        }
        Mock Test-OpPreflight { [pscustomobject]@{ Label = 'Espace libre'; Result = 'Ok'; Message = 'ok'; Action = $null } }
        $script:plan = @((Get-Row 'def' 'defender'), (Get-Row 'lcu' 'windows-lcu' $true), (Get-Row 'dot' 'dotnet' $true), (Get-Row 'off' 'office-source'))
        # Plan recalculé : une étape installée passe à UpToDate.
        $script:installed = @{}
        Mock Get-OpInstallPlan { $script:plan | ForEach-Object { $r = $_.PSObject.Copy(); if ($script:installed.ContainsKey($r.Id)) { $r.State = 'UpToDate' }; $r } }
        Mock Read-OpManifest { [pscustomobject]@{ generatedAt = '2026-10-14T09:12:00Z'; items = @($script:plan | ForEach-Object { [pscustomobject]@{ id = $_.Id; category = $_.Category } }) } }
        Mock New-OpRestorePoint { [pscustomobject]@{ Status = 'Created'; Description = 'OffPatch'; CreationTime = Get-Date; Reason = $null; ProtectionEnabled = $true } }
        Mock Install-OpDefenderUpdate { Get-Result $Item.id 'defender' }
        Mock Install-OpWindowsPackage { $r = Get-Result $Item.id $Item.category; $r | Add-Member RebootRequired $true; $r }
        Mock Install-OpOfficeUpdate { Get-Result $Item.id 'office-source' }
        Mock Get-OpNetworkConnection { }
        # Planificateur de tâches simulé : la tâche existe entre son enregistrement et sa suppression.
        $script:task = $null
        Mock Register-ScheduledTask { $script:task = [pscustomobject]@{ TaskName = $TaskName } }
        Mock Get-ScheduledTask { if ($script:task -and $script:task.TaskName -eq $TaskName) { $script:task } }
        Mock Unregister-ScheduledTask { $script:task = $null }
    }

    It 'enchaîne étapes, redémarrages avec reprise, rapport et nettoyage' {
        (Invoke-OpInstallStep -StepId 'def' -Root $script:root).State | Should -Be 'UpToDate'
        (Invoke-OpInstallStep -StepId 'lcu' -Root $script:root).RebootAfter | Should -BeTrue

        $restart = Restart-OpSession -Root $script:root
        $restart.Result | Should -Be 'Restarting'
        $restart.RebootCount | Should -Be 1
        Should -Invoke Restart-Computer -Times 1 -Exactly
        $script:task.TaskName | Should -Be 'OffPatch-Reprise'
        Test-Path -LiteralPath (Get-ProgramData 'resume.ps1') | Should -BeTrue
        $state = Read-OpSessionState
        $state.rebootCount | Should -Be 1
        $state.support.volumeSerial | Should -Be 'D29F1400'
        @($state.steps | ForEach-Object { $_.Id }) | Should -Be @('def', 'lcu')

        # Après la reprise : la session continue sur le même état.
        (Invoke-OpInstallStep -StepId 'dot' -Root $script:root).RebootAfter | Should -BeTrue
        (Restart-OpSession -Root $script:root).RebootCount | Should -Be 2
        (Invoke-OpInstallStep -StepId 'off' -Root $script:root).State | Should -Be 'UpToDate'
        (Read-OpSessionState).sessionId | Should -Be $state.sessionId
        Should -Invoke New-OpRestorePoint -Times 1 -Exactly

        $path = Write-OpInstallReport -Root $script:root -WarningVariable warnings -WarningAction SilentlyContinue
        $html = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        foreach ($id in 'def', 'lcu', 'dot', 'off') { $html | Should -Match "fait $id" }
        $html | Should -Match 'mode Avion'
        "$warnings" | Should -Match 'mode Avion'
        $script:task | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Get-ProgramData 'resume.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Get-ProgramData 'temp') | Should -BeFalse
        Test-Path -LiteralPath (Get-ProgramData 'state.json') | Should -BeFalse
        $archive = @(Get-ChildItem -Path (Get-ProgramData 'logs') -Filter 'state_*.json')
        $archive.Count | Should -Be 1
        (Get-Content -LiteralPath $archive[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json).rebootCount | Should -Be 2
    }

    It 'limite de redémarrages atteinte : pas de redémarrage, la session se termine par le rapport' {
        $script:maxReboots = 1
        Invoke-OpInstallStep -StepId 'lcu' -Root $script:root | Out-Null
        (Restart-OpSession -Root $script:root).Result | Should -Be 'Restarting'
        Invoke-OpInstallStep -StepId 'dot' -Root $script:root | Out-Null
        $refused = Restart-OpSession -Root $script:root
        $refused.Result | Should -Be 'Refused'
        $refused.RebootCount | Should -Be 1
        Should -Invoke Restart-Computer -Times 1 -Exactly
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*maxAutoReboots*' }

        Write-OpInstallReport -Root $script:root -WarningAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $script:task | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Get-ProgramData 'state.json') | Should -BeFalse
    }

    It 'redémarrage annulé : tâche retirée, la session continue sans redémarrer' {
        Invoke-OpInstallStep -StepId 'lcu' -Root $script:root | Out-Null
        (Restart-OpSession -Root $script:root -IsCancelled { $true }).Result | Should -Be 'Cancelled'
        $script:task | Should -BeNullOrEmpty
        Should -Invoke Restart-Computer -Times 0 -Exactly
        (Read-OpSessionState).rebootCount | Should -Be 0
        (Invoke-OpInstallStep -StepId 'off' -Root $script:root).State | Should -Be 'UpToDate'
        @((Read-OpSessionState).steps | ForEach-Object { $_.Id }) | Should -Be @('lcu', 'off')
    }

    Context 'Invoke-OpAutoSession' {
        It 'déroule le plan : redémarre après lcu puis dot, termine par le rapport à la troisième reprise' {
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false
            $r.Result | Should -Be 'Restarting'
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('def', 'lcu')
            (Read-OpSessionState).mode | Should -Be 'Auto'
            $script:task.TaskName | Should -Be 'OffPatch-Reprise'

            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false
            $r.Result | Should -Be 'Restarting'
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('dot')

            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue
            $r.Result | Should -Be 'Completed'
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('off')
            Test-Path -LiteralPath $r.ReportPath | Should -BeTrue
            Should -Invoke Restart-Computer -Times 2 -Exactly
            $script:task | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Get-ProgramData 'state.json') | Should -BeFalse
        }

        It 'retente une étape en erreur une fois, l''abandonne et continue' {
            $script:plan = @((Get-Row 'off' 'office-source'), (Get-Row 'def' 'defender'))
            Mock Install-OpOfficeUpdate { [pscustomobject]@{ Id = $Item.id; Category = 'office-source'; State = 'Error'; Reason = 'ODT en échec'; ExitCode = 17 } }
            $steps = New-Object System.Collections.Generic.List[object]
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue -OnStep { param($s) $steps.Add($s) }
            $r.Result | Should -Be 'Completed'
            Should -Invoke Install-OpOfficeUpdate -Times 2 -Exactly
            Should -Invoke Install-OpDefenderUpdate -Times 1 -Exactly
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('off', 'off', 'def')
            $r.Steps[1].Abandoned | Should -BeTrue
            $steps.Count | Should -Be 6
        }

        It 'limite de redémarrages atteinte : s''arrête et termine par le rapport' {
            $script:maxReboots = 0
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue
            $r.Result | Should -Be 'Completed'
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('def', 'lcu')
            Should -Invoke Restart-Computer -Times 0 -Exactly
            $r.ReportPath | Should -Not -BeNullOrEmpty
        }

        It 'redémarrage annulé : Cancelled, état conservé pour la reprise' {
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -IsCancelled { $true }
            $r.Result | Should -Be 'Cancelled'
            Test-Path -LiteralPath (Get-ProgramData 'state.json') | Should -BeTrue
            Should -Invoke Restart-Computer -Times 0 -Exactly
        }

        It 'rien à installer : rapport sans session ni redémarrage' {
            $script:plan = @((Get-Row 'def' 'defender') | ForEach-Object { $_.State = 'UpToDate'; $_ })
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue
            $r.Result | Should -Be 'Completed'
            $r.Steps.Count | Should -Be 0
            Test-Path -LiteralPath $r.ReportPath | Should -BeTrue
            Should -Invoke Install-OpDefenderUpdate -Times 0 -Exactly
        }

        It 'refuse <Cas> sans rien exécuter' -TestCases @(
            @{ Cas = 'une session manuelle en cours'; Manual = $true; Blocking = $false; Pattern = '*Session manuelle*' }
            @{ Cas = 'un contrôle préalable bloquant'; Manual = $false; Blocking = $true; Pattern = '*bloquant*' }
        ) {
            param($Manual, $Blocking, $Pattern)
            if ($Manual) { Invoke-OpInstallStep -StepId 'def' -Root $script:root | Out-Null }
            if ($Blocking) { Mock Test-OpPreflight { [pscustomobject]@{ Label = 'Droits'; Result = 'Blocking'; Message = 'non élevé'; Action = $null } } }
            { Invoke-OpAutoSession -Root $script:root -Confirm:$false } | Should -Throw $Pattern
            Should -Invoke Install-OpWindowsPackage -Times 0 -Exactly
        }

        It 'Windows 10 sans ESU : étapes Windows et .NET ignorées et signalées, les autres exécutées' {
            Mock Test-OpPreflight { [pscustomobject]@{ Label = 'ESU Windows 10'; Result = 'Warning'; Message = 'ESU absent'; Action = 'SkipWindowsInAuto' } }
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue
            $r.Result | Should -Be 'Completed'
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('def', 'off')
            Should -Invoke Install-OpWindowsPackage -Times 0 -Exactly
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*lcu ignorée*ESU*' }
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*dot ignorée*ESU*' }
        }

        It 'Windows 10 sans ESU avec -ForceWindows : étapes Windows exécutées, forçage gardé à la reprise' {
            Mock Test-OpPreflight { [pscustomobject]@{ Label = 'ESU Windows 10'; Result = 'Warning'; Message = 'ESU absent'; Action = 'SkipWindowsInAuto' } }
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -ForceWindows
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('def', 'lcu')
            (Read-OpSessionState).forceWindows | Should -BeTrue
            $script:plan += Get-Row 'ssu' 'windows-ssu'
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('dot')
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false -WarningAction SilentlyContinue
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('off', 'ssu')
        }

        It 'cumulative annulée au redémarrage (0x800f0922 sans ESU) : erreur à la reprise, sans réinstallation' {
            # La cumulative s'installe (3010) mais reste à installer après le redémarrage.
            Mock Install-OpWindowsPackage {
                $r = [pscustomobject]@{ Id = $Item.id; Category = $Item.category; State = 'UpToDate'; Reason = 'Package_for_RollupFix : InstallPending.'; ExitCode = 3010 }
                if ($Item.id -ne 'lcu') { $script:installed[$Item.id] = $true }
                $r | Add-Member RebootRequired $true
                $r
            }
            (Invoke-OpAutoSession -Root $script:root -Confirm:$false).Result | Should -Be 'Restarting'
            $r = Invoke-OpAutoSession -Root $script:root -Confirm:$false
            @($r.Steps | ForEach-Object { $_.Id }) | Should -Be @('dot')
            Should -Invoke Install-OpWindowsPackage -Times 1 -Exactly -ParameterFilter { $Item.id -eq 'lcu' }
            $lcu = @((Read-OpSessionState).steps | Where-Object { $_.Id -eq 'lcu' })[0]
            $lcu.State | Should -Be 'Error'
            $lcu.Reason | Should -BeLike '*non appliquée après redémarrage*'
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*lcu*retour arrière*' }
        }

        It 'ne fait rien avec -WhatIf' {
            Invoke-OpAutoSession -Root $script:root -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Install-OpDefenderUpdate -Times 0 -Exactly
            Test-Path -LiteralPath (Get-ProgramData 'state.json') | Should -BeFalse
        }
    }
}
