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
