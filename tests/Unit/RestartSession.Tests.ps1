# Redémarrage de session automatique (cahier des charges 8.6) : limite maxAutoReboots, tâche de reprise, compte à
# rebours avec annulation, rebootCount écrit avant le redémarrage. Restart-Computer et la tâche planifiée sont
# toujours simulés : rien ne redémarre.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpRoot', 'Get-OpPath', 'Get-OpConfiguration', 'Read-OpSessionState', 'Save-OpSessionState', 'Register-OpResumeTask', 'Unregister-OpResumeTask') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    . (Join-Path $repo 'app\module\OffPatch\Public\Restart-OpSession.ps1')
}

Describe 'Restart-OpSession' {
    BeforeEach {
        Mock Restart-Computer {}
        Mock Start-Sleep {}
        Mock Write-OpLog {}
        Mock Register-OpResumeTask { [pscustomobject]@{ TaskName = 'OffPatch-Reprise' } }
        Mock Unregister-OpResumeTask { $true }
        Mock Get-OpConfiguration { [pscustomobject]@{ Settings = [pscustomobject]@{ client = [pscustomobject]@{ maxAutoReboots = 3; rebootCountdownSeconds = 5 } } } }
        $script:state = Join-Path $TestDrive "state-$([guid]::NewGuid()).json"
        Mock Get-OpPath { $script:state } -ParameterFilter { $Name -eq 'State' }
    }
    BeforeAll {
        function Initialize-TestSession([int]$Reboots) {
            Save-OpSessionState -State ([pscustomobject]@{ schemaVersion = 1; sessionId = 's1'; rebootCount = $Reboots; steps = @() }) -Path $script:state
        }
    }

    It 'crée la tâche, décompte, écrit rebootCount puis redémarre' {
        Initialize-TestSession 1
        $script:ticks = New-Object System.Collections.Generic.List[int]
        $r = Restart-OpSession -Root $TestDrive -OnTick { param($s) $script:ticks.Add($s) }
        $r.Result | Should -Be 'Restarting'
        $r.RebootCount | Should -Be 2
        @($script:ticks) | Should -Be @(5, 4, 3, 2, 1)
        (Read-OpSessionState -Path $script:state).rebootCount | Should -Be 2
        Should -Invoke Register-OpResumeTask -Times 1 -Exactly
        Should -Invoke Restart-Computer -Times 1 -Exactly -ParameterFilter { $Force }
        Should -Invoke Start-Sleep -Times 5 -Exactly
    }

    It 'annulé pendant le compte à rebours : tâche retirée, état inchangé, aucun redémarrage' {
        Initialize-TestSession 0
        $script:calls = 0
        $r = Restart-OpSession -Root $TestDrive -IsCancelled { $script:calls++; $script:calls -ge 3 }
        $r.Result | Should -Be 'Cancelled'
        (Read-OpSessionState -Path $script:state).rebootCount | Should -Be 0
        Should -Invoke Unregister-OpResumeTask -Times 1 -Exactly
        Should -Invoke Restart-Computer -Times 0 -Exactly
    }

    It 'refuse au-delà de maxAutoReboots, sans tâche ni redémarrage' {
        Initialize-TestSession 3
        $r = Restart-OpSession -Root $TestDrive
        $r.Result | Should -Be 'Refused'
        Should -Invoke Register-OpResumeTask -Times 0 -Exactly
        Should -Invoke Restart-Computer -Times 0 -Exactly
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -match 'maxAutoReboots' }
    }

    It 'redémarre aussitôt avec un compte à rebours nul' {
        Initialize-TestSession 0
        (Restart-OpSession -Root $TestDrive -CountdownSeconds 0).Result | Should -Be 'Restarting'
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'refuse sans session en cours, et respecte -WhatIf' {
        { Restart-OpSession -Root $TestDrive } | Should -Throw '*Aucune session*'
        Initialize-TestSession 0
        Restart-OpSession -Root $TestDrive -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Register-OpResumeTask -Times 0 -Exactly
        Should -Invoke Restart-Computer -Times 0 -Exactly
        (Read-OpSessionState -Path $script:state).rebootCount | Should -Be 0
    }
}
