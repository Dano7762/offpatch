# Journal (cahier des charges, section 10) : fichiers, format, niveaux, file de messages, masquage des clés.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Start-OpLog', 'ConvertTo-OpMaskedText', 'Write-OpLog') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $moment = [datetime]'2026-10-14T09:12:03'
}

Describe 'Start-OpLog' {
    It 'nomme le journal du dépôt depot_AAAA-MM-JJ_HHMMSS.log, sans sous-dossier' {
        $log = Start-OpLog -Kind Depot -Directory (Join-Path $TestDrive 'logs') -Now $moment
        Split-Path -Leaf $log.Path | Should -Be 'depot_2026-10-14_091203.log'
        $log.ToolLogDirectory | Should -BeNullOrEmpty
    }

    It 'crée pour une session le sous-dossier des journaux de DISM et de l''ODT' {
        $log = Start-OpLog -Kind Session -Directory (Join-Path $TestDrive 'pd') -Now $moment
        Split-Path -Leaf $log.Path | Should -Be 'session_2026-10-14_091203.log'
        Test-Path -Path $log.ToolLogDirectory -PathType Container | Should -BeTrue
    }

    It 'place par défaut le journal de session dans ProgramData\OffPatch\logs' {
        $saved = $env:ProgramData
        try {
            $env:ProgramData = Join-Path $TestDrive 'ProgramData'
            $log = Start-OpLog -Kind Session -Now $moment
            $log.Path | Should -Be (Join-Path $TestDrive 'ProgramData\OffPatch\logs\session_2026-10-14_091203.log')
        } finally { $env:ProgramData = $saved }
    }
}

Describe 'Write-OpLog' {
    BeforeEach {
        $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $log = Start-OpLog -Kind Depot -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Level INFO -Queue $queue -Now $moment
    }

    It 'écrit une ligne au format « date heure [NIVEAU] message »' {
        Write-OpLog 'Dépôt mis à jour' -Level INFO -Now $moment
        @(Get-Content -Path $log.Path -Encoding UTF8) | Should -Be @('2026-10-14 09:12:03 [INFO] Dépôt mis à jour')
    }

    It 'ignore les lignes sous le niveau minimal' {
        Write-OpLog 'détail' -Level DEBUG -Now $moment
        Write-OpLog 'attention' -Level WARN -Now $moment
        @(Get-Content -Path $log.Path -Encoding UTF8) | Should -Be @('2026-10-14 09:12:03 [WARN] attention')
    }

    It 'dépose chaque ligne écrite dans la file de messages de l''interface' {
        Write-OpLog 'un' -Now $moment
        Write-OpLog 'deux' -Level ERROR -Now $moment
        $queue.Count | Should -Be 2
        $item = $null
        $queue.TryDequeue([ref]$item) | Should -BeTrue
        $item.Message | Should -Be 'un'
    }

    It 'masque une clé de produit avant l''écriture' {
        Write-OpLog 'Clé saisie : ABCDE-12345-FGHIJ-67890-KLMNO pour le profil LTSC' -Now $moment
        $content = Get-Content -Path $log.Path -Raw -Encoding UTF8
        $content | Should -Not -Match 'ABCDE-12345'
        $content | Should -Match 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
    }
}

Describe 'Write-OpLog sans journal ouvert' {
    It 'n''interrompt pas l''outil et passe la ligne au flux Verbose' {
        Remove-Variable -Name OpLog -Scope Script -ErrorAction SilentlyContinue
        $verbose = Write-OpLog 'sans journal' -Now $moment -Verbose 4>&1
        "$verbose" | Should -Be '2026-10-14 09:12:03 [INFO] sans journal'
    }
}
