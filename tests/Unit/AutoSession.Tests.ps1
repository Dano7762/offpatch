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
    foreach ($name in 'Get-OpSystemInfo', 'Test-OpPreflight', 'Get-OpInstallPlan', 'Invoke-OpInstallStep', 'Restart-OpSession', 'Write-OpInstallReport') {
        . (Join-Path $repo "app\module\OffPatch\Public\$name.ps1")
    }

    function Get-Row([string]$Id, [string]$Category, [bool]$RebootAfter = $false) {
        [pscustomobject]@{ Sequence = 1; Id = $Id; Category = $Category; State = 'Pending'; Reason = "motif $Id"; Installed = $null; Available = '1'; RebootAfter = $RebootAfter }
    }
    function Get-Result([string]$Id, [string]$Category) {
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
        Mock Test-OpPreflight { [pscustomobject]@{ Label = 'Espace libre'; Result = 'Ok'; Message = 'ok' } }
        $script:plan = @((Get-Row 'def' 'defender'), (Get-Row 'lcu' 'windows-lcu' $true), (Get-Row 'dot' 'dotnet' $true), (Get-Row 'off' 'office-source'))
        Mock Get-OpInstallPlan { $script:plan }
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
}
