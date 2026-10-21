# Traitements longs de l'interface (cahier des charges 9) : runspace séparé avec le module OffPatch, file de
# messages, relève sans attente, annulation coopérative, relais par le Dispatcher. Vrais runspaces, aucun accès au
# système hors du TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'app\gui\Background.ps1')
    $script:modulePath = Join-Path $repo 'app\module\OffPatch\OffPatch.psd1'

    # Relève jusqu'à la fin (ou le délai), en cumulant les messages ; renvoie le dernier relevé et tous les messages.
    function Wait-TestTask($Task, [int]$Seconds = 60) {
        $all = New-Object System.Collections.Generic.List[object]
        $deadline = (Get-Date).AddSeconds($Seconds)
        do {
            $r = Receive-OpBackgroundTask -Task $Task
            foreach ($m in $r.Messages) { $all.Add($m) }
            if (-not $r.Completed) { Start-Sleep -Milliseconds 50 }
        } until ($r.Completed -or (Get-Date) -gt $deadline)
        [pscustomobject]@{ Last = $r; Messages = $all.ToArray() }
    }
    function Invoke-TestTask([scriptblock]$ScriptBlock, [hashtable]$Parameters = @{}) {
        Start-OpBackgroundTask -ScriptBlock $ScriptBlock -Parameters $Parameters -ModulePath $script:modulePath -Confirm:$false
    }
}

Describe 'Start-OpBackgroundTask et Receive-OpBackgroundTask' {
    It 'charge le module OffPatch dans le runspace et transmet les paramètres' {
        $t = Invoke-TestTask { param($Value) (Get-Command Initialize-OpSession).Module.Name; $Value * 2 } @{ Value = 21 }
        $w = Wait-TestTask $t
        $w.Last.Completed | Should -BeTrue
        $w.Last.Output | Should -Be @('OffPatch', 42)
        $w.Last.Error | Should -BeNullOrEmpty
        $t.Done | Should -BeTrue
    }

    It 'relaie dans l''ordre les messages déposés dans la file, puis rien après la fin' {
        $t = Invoke-TestTask { foreach ($i in 1..5) { $OpQueue.Enqueue([pscustomobject]@{ Line = "ligne $i" }) } }
        $w = Wait-TestTask $t
        @($w.Messages | ForEach-Object { $_.Line }) | Should -Be @('ligne 1', 'ligne 2', 'ligne 3', 'ligne 4', 'ligne 5')
        $again = Receive-OpBackgroundTask -Task $t
        $again.Completed | Should -BeTrue
        $again.Messages.Count | Should -Be 0
    }

    It 'reçoit les lignes du journal du module (Initialize-OpSession -Queue)' {
        $root = Join-Path $TestDrive 'outil'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Copy-Item -Path (Join-Path $repo 'offpatch.root') -Destination $root
        Copy-Item -Path (Join-Path $repo 'config') -Destination $root -Recurse
        $t = Invoke-TestTask { param($Root) [void](Initialize-OpSession -Kind Depot -Queue $OpQueue -Root $Root) } @{ Root = $root }
        $w = Wait-TestTask $t
        $w.Last.Error | Should -BeNullOrEmpty
        $w.Messages[0].Level | Should -Be 'INFO'
        $w.Messages[0].Line | Should -Match '\[INFO\] OffPatch, opération Depot'
        @(Get-ChildItem -Path (Join-Path $root 'logs') -Filter 'depot_*.log').Count | Should -Be 1
    }

    It 'rend compte d''une erreur bloquante du traitement' {
        $w = Wait-TestTask (Invoke-TestTask { throw 'échec simulé' })
        $w.Last.Completed | Should -BeTrue
        $w.Last.Error | Should -Be 'échec simulé'
    }

    It 'ne bloque pas pendant le traitement' {
        $t = Invoke-TestTask { Start-Sleep -Seconds 3; 'fin' }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Receive-OpBackgroundTask -Task $t
        $watch.Stop()
        $r.Completed | Should -BeFalse
        $watch.ElapsedMilliseconds | Should -BeLessThan 1000
        (Wait-TestTask $t).Last.Output | Should -Be 'fin'
    }
}

Describe 'Stop-OpBackgroundTask' {
    It 'annule un traitement qui consulte le jeton' {
        $t = Invoke-TestTask { while (-not $OpCancel.IsCancellationRequested) { Start-Sleep -Milliseconds 50 }; 'arrêté proprement' }
        Start-Sleep -Milliseconds 300
        (Receive-OpBackgroundTask -Task $t).Completed | Should -BeFalse
        Stop-OpBackgroundTask -Task $t -Confirm:$false
        $w = Wait-TestTask $t 20
        $w.Last.Completed | Should -BeTrue
        $w.Last.Cancelled | Should -BeTrue
        $w.Last.Output | Should -Be 'arrêté proprement'
    }

    It 'ne fait rien avec -WhatIf ni sur une tâche terminée' {
        $t = Invoke-TestTask { 'ok' }
        Stop-OpBackgroundTask -Task $t -WhatIf
        $w = Wait-TestTask $t
        $w.Last.Cancelled | Should -BeFalse
        { Stop-OpBackgroundTask -Task $t -Confirm:$false } | Should -Not -Throw
    }
}

Describe 'Register-OpBackgroundPump' -Skip:$script:noSta {
    It 'relaie messages et fin sur le thread appelant, par le Dispatcher' {
        Add-Type -AssemblyName WindowsBase
        $script:pumpMessages = New-Object System.Collections.Generic.List[string]
        $script:pumpThreads = New-Object System.Collections.Generic.List[int]
        $script:pumpResult = $null
        $script:frame = New-Object System.Windows.Threading.DispatcherFrame
        $t = Invoke-TestTask { foreach ($i in 1..3) { $OpQueue.Enqueue([pscustomobject]@{ Line = "ligne $i" }); Start-Sleep -Milliseconds 100 }; 'terminé' }
        $timer = Register-OpBackgroundPump -Task $t -IntervalMilliseconds 50 -OnMessage {
            param($m)
            $script:pumpMessages.Add($m.Line)
            $script:pumpThreads.Add([System.Threading.Thread]::CurrentThread.ManagedThreadId)
        } -OnCompleted {
            param($r)
            $script:pumpResult = $r
            $script:frame.Continue = $false
        }
        # Garde-fou : la boucle du Dispatcher s'arrête au plus tard après 30 s.
        $guard = New-Object System.Windows.Threading.DispatcherTimer
        $guard.Interval = [timespan]::FromSeconds(30)
        $guard.Add_Tick({ $script:frame.Continue = $false })
        $guard.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($script:frame)
        $guard.Stop()
        $timer.IsEnabled | Should -BeFalse
        @($script:pumpMessages) | Should -Be @('ligne 1', 'ligne 2', 'ligne 3')
        @($script:pumpThreads | Select-Object -Unique) | Should -Be @([System.Threading.Thread]::CurrentThread.ManagedThreadId)
        $script:pumpResult.Output | Should -Be 'terminé'
    }
}
