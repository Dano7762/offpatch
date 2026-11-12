# Avancement dans la console de la CLI (Write-OpProgress) : seulement si le journal est ouvert avec -Console, jamais
# écrit au journal ; tailles à la française (Format-OpSize).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpPath', 'Start-OpLog', 'Format-OpSize', 'Write-OpProgress') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
}

Describe 'Format-OpSize' {
    It 'écrit <Bytes> octets en « <Text> »' -TestCases @(
        @{ Bytes = 4778000000; Text = '4,45 Go' }
        @{ Bytes = 533725184; Text = '509,0 Mo' }
        @{ Bytes = $null; Text = 'taille inconnue' }
    ) {
        param($Bytes, $Text)
        (Format-OpSize $Bytes) -replace [char]0xA0, ' ' -replace [char]0x202F, ' ' | Should -Be $Text
    }
}

Describe 'Write-OpProgress' {
    AfterEach { $script:OpLog = $null }

    It 'n''affiche rien sans -Console, et n''écrit rien au journal' {
        $log = Start-OpLog -Kind Depot -Directory (Join-Path $TestDrive 'a')
        (Write-OpProgress 'Fichier 1/2' 6>&1) | Should -BeNullOrEmpty
        Test-Path -LiteralPath $log.Path | Should -BeFalse
    }

    It 'affiche l''heure, le message et l''avancement avec -Console, sans l''écrire au journal' {
        $log = Start-OpLog -Kind Depot -Directory (Join-Path $TestDrive 'b') -Console
        $out = [string](Write-OpProgress '  BITS :' -Bytes 1GB -TotalBytes 4GB 6>&1)
        $out | Should -Match '^\d{2}:\d{2}:\d{2}   BITS : 1,00 Go / 4,00 Go \(25 %\)$'
        Test-Path -LiteralPath $log.Path | Should -BeFalse
    }

    It 'affiche les octets reçus quand le total est inconnu' {
        $null = Start-OpLog -Kind Depot -Directory (Join-Path $TestDrive 'c') -Console
        [string](Write-OpProgress '  HttpClient :' -Bytes 10MB 6>&1) | Should -Match 'HttpClient : 10,0 Mo reçus$'
    }
}

Describe 'Write-OpProgress : messages structurés et cadence' {
    BeforeEach {
        $script:queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:OpLog = [pscustomobject]@{ Path = (Join-Path $TestDrive 'p.log'); Level = 'INFO'; Queue = $script:queue; Console = $true }
        $script:OpProgressFile = $null
        $script:OpProgressLast = $null
        Mock Write-Host {}
    }
    AfterEach { $script:OpLog = $null; $script:OpProgressFile = $null; $script:OpProgressLast = $null }
    BeforeAll {
        function Get-QueuedMessage { $m = $null; $list = @(); while ($script:queue.TryDequeue([ref]$m)) { $list += $m }; $list }
    }

    It 'fichier en cours : fichier i/n, nom, octets et % du fichier, % global et Value en octets' {
        $script:OpProgressFile = @{ Index = 2; Count = 3; Name = 'lcu.msu'; Size = 4GB; Done = [double]2GB; Total = [double]8GB }
        Write-OpProgress '  BITS :' -Bytes 1GB -TotalBytes 4GB
        $m = @(Get-QueuedMessage)
        $m.Count | Should -Be 1
        $m[0].Message -replace '[  ]', ' ' | Should -Be 'Fichier 2/3 : lcu.msu, 1,00 Go / 4,00 Go (25 %) ; total 38 %'
        $m[0].Value | Should -Be 0.375
        $m[0].Indeterminate | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -match 'BITS : 1,00 Go / 4,00 Go \(25 %\)$' }
    }

    It 'sans fichier en cours : Value nulle ; Indeterminate transmis (ODT, sources Office)' {
        Write-OpProgress 'Source Office : setup.exe /download en cours' -Indeterminate
        $m = @(Get-QueuedMessage)
        $m[0].Message | Should -Be 'Source Office : setup.exe /download en cours'
        $m[0].Value | Should -BeNullOrEmpty
        $m[0].Indeterminate | Should -BeTrue
    }

    It 'Throttle : interface au plus toutes les 2 s, console au plus toutes les 30 s' {
        Write-OpProgress 'Fichier 1/1' # début du fichier : délais remis à zéro
        $null = Get-QueuedMessage
        Write-OpProgress '  BITS :' -Bytes 1 -TotalBytes 10 -Throttle
        @(Get-QueuedMessage).Count | Should -Be 0
        $script:OpProgressLast.Queue = (Get-Date).AddSeconds(-3)
        Write-OpProgress '  BITS :' -Bytes 2 -TotalBytes 10 -Throttle
        Write-OpProgress '  BITS :' -Bytes 3 -TotalBytes 10 -Throttle
        @(Get-QueuedMessage).Count | Should -Be 1
        Should -Invoke Write-Host -Times 1 -Exactly # seulement « Fichier 1/1 »
        $script:OpProgressLast.Console = (Get-Date).AddSeconds(-31)
        Write-OpProgress '  BITS :' -Bytes 4 -TotalBytes 10 -Throttle
        Should -Invoke Write-Host -Times 2 -Exactly
        @(Get-QueuedMessage).Count | Should -Be 0
    }

    It 'Throttle sans message préalable : rien de suite, la cadence part de cet appel' {
        Write-OpProgress '  HttpClient :' -Bytes 1 -Throttle
        @(Get-QueuedMessage).Count | Should -Be 0
        Should -Invoke Write-Host -Times 0 -Exactly
        $script:OpProgressLast | Should -Not -BeNullOrEmpty
    }
}
