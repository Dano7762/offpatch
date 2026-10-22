# Onglet « Journal » (cahier des charges 9, 10) : filtre par niveau sur une vraie fenêtre chargée sans affichage
# (thread STA requis, sinon ces tests sont ignorés), choix du dossier des journaux, ouverture des dossiers (Invoke-Item
# simulé : aucun Explorateur ouvert).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $script:noSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
}

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'MainWindow', 'LogTab') { . (Join-Path $repo "app\gui\$name.ps1") }

    function Get-TestMessage([string]$Level, [string]$Text) {
        [pscustomobject]@{ Time = Get-Date; Level = $Level; Message = $Text; Line = "2026-10-22 09:00:00 [$Level] $Text" }
    }
}

Describe 'Journal en direct et filtre par niveau' -Skip:$script:noSta {
    BeforeEach {
        $script:ui = Import-OpMainWindow
        Register-OpLogTab -Ui $script:ui -Root $TestDrive
        $script:c = $script:ui.Controls
    }

    It 'affiche toutes les lignes, ignore l''avancement, filtre puis réaffiche les lignes gardées' {
        foreach ($level in 'DEBUG', 'INFO', 'WARN', 'ERROR') { Add-OpJournalEntry -Controls $c -Message (Get-TestMessage $level $level.ToLower()) }
        Add-OpJournalEntry -Controls $c -Message ([pscustomobject]@{ Kind = 'Progress'; Message = '50 %' })
        $c.LogList.Items.Count | Should -Be 4

        $c.LogLevelFilter.SelectedIndex = 2
        @($c.LogList.Items) | Should -Be @('2026-10-22 09:00:00 [WARN] warn', '2026-10-22 09:00:00 [ERROR] error')
        Add-OpJournalEntry -Controls $c -Message (Get-TestMessage 'INFO' 'masquée')
        Add-OpJournalEntry -Controls $c -Message (Get-TestMessage 'ERROR' 'visible')
        $c.LogList.Items.Count | Should -Be 3

        $c.LogLevelFilter.SelectedIndex = 0
        $c.LogList.Items.Count | Should -Be 6
        $c.LogList.Items[4] | Should -BeLike '*masquée'
    }

    It 'garde au plus le nombre de lignes prévu' {
        $saved = $script:OpJournalMaxLines
        try {
            $script:OpJournalMaxLines = 3
            1..5 | ForEach-Object { Add-OpJournalEntry -Controls $c -Message (Get-TestMessage 'INFO' "ligne $_") }
            @($c.LogList.Items) | Should -Be @(3..5 | ForEach-Object { "2026-10-22 09:00:00 [INFO] ligne $_" })
            $c.LogList.Tag.Count | Should -Be 3
        } finally { $script:OpJournalMaxLines = $saved }
    }
}

Describe 'Get-OpLogFolder' {
    BeforeEach {
        $script:savedProgramData = $env:ProgramData
        $env:ProgramData = Join-Path $TestDrive 'pd'
        $script:tool = Join-Path $TestDrive 'outil'
        Remove-Item -LiteralPath $env:ProgramData, $script:tool -Recurse -Force -ErrorAction SilentlyContinue
    }
    AfterEach { $env:ProgramData = $script:savedProgramData }

    It 'aucun dossier de journaux : rien' {
        Get-OpLogFolder -Root $tool | Should -BeNullOrEmpty
    }

    It 'dossiers sans journal : celui de l''outil' {
        New-Item -ItemType Directory -Force -Path (Join-Path $tool 'logs'), (Join-Path $env:ProgramData 'OffPatch\logs') | Out-Null
        Get-OpLogFolder -Root $tool | Should -Be (Join-Path $tool 'logs')
    }

    It 'dossier du journal le plus récent : <Cas>' -TestCases @(
        @{ Cas = 'session du PC client'; Newer = 'client' }
        @{ Cas = 'dépôt de l''outil'; Newer = 'tool' }
    ) {
        $folders = @{ tool = (Join-Path $tool 'logs'); client = (Join-Path $env:ProgramData 'OffPatch\logs') }
        New-Item -ItemType Directory -Force -Path $folders.tool, $folders.client | Out-Null
        $toolLog = New-Item -ItemType File -Path (Join-Path $folders.tool 'depot.log')
        $clientLog = New-Item -ItemType File -Path (Join-Path $folders.client 'session.log')
        $old = (Get-Date).AddHours(-1)
        if ($Newer -eq 'client') { $toolLog.LastWriteTimeUtc = $old.ToUniversalTime() } else { $clientLog.LastWriteTimeUtc = $old.ToUniversalTime() }
        Get-OpLogFolder -Root $tool | Should -Be $folders[$Newer]
    }
}

Describe 'Open-OpFolder' {
    BeforeEach { Mock Invoke-Item {} }

    It 'dossier absent ou vide : faux, rien d''ouvert' {
        Open-OpFolder -Path (Join-Path $TestDrive 'absent') | Should -BeFalse
        Open-OpFolder -Path '' | Should -BeFalse
        Should -Invoke Invoke-Item -Times 0 -Exactly
    }

    It 'dossier présent : ouvert dans l''Explorateur' {
        Open-OpFolder -Path $TestDrive | Should -BeTrue
        Should -Invoke Invoke-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $TestDrive }
    }
}
