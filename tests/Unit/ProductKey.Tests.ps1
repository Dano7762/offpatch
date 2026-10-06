# Clé de produit (R-08, cahier des charges 8.5 et 11) : forme contrôlée avant l'ODT, masquage dans les textes et dans
# les journaux de l'ODT (UTF-16 réécrit en UTF-16). Fixture : journal principal synthétique, fausse clé conforme.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Protect-OpLogFile', 'Test-OpProductKeyFormat') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $fakeKey = 'BCDFG-HJKMP-QRTVW-XY234-6789B'
    $fixture = Join-Path $root 'tests\Fixtures\odt\odt-journal-principal-utf16.log'
}

Describe 'Test-OpProductKeyFormat' {
    It 'accepte <Cle>' -TestCases @(
        @{ Cle = 'BCDFG-HJKMP-QRTVW-XY234-6789B' }
        @{ Cle = 'bcdfg-hjkmp-qrtvw-xy234-6789b' }
        @{ Cle = ' BCDFG-HJKMP-QRTVW-XY234-6789B ' }
    ) {
        param($Cle)
        Test-OpProductKeyFormat -ProductKey $Cle | Should -BeTrue
    }

    It 'refuse <Cle> (<Motif>)' -TestCases @(
        @{ Cle = 'ABCDE-HJKMP-QRTVW-XY234-6789B'; Motif = 'voyelle hors alphabet' }
        @{ Cle = 'BCDFG-HJKMP-QRTVW-XY234-6789'; Motif = 'dernier groupe trop court' }
        @{ Cle = 'BCDFGHJKMPQRTVWXY2346789B'; Motif = 'sans tirets' }
        @{ Cle = 'BCDF0-HJKMP-QRTVW-XY234-6789B'; Motif = 'chiffre 0 hors alphabet' }
        @{ Cle = 'BCDF1-HJKMP-QRTVW-XY234-6789B'; Motif = 'chiffre 1 hors alphabet' }
        @{ Cle = 'BCDFG-HJKMP-QRTVW-XY234-6789B-BCDFG'; Motif = 'six groupes' }
        @{ Cle = ''; Motif = 'vide' }
    ) {
        param($Cle, $Motif)
        Test-OpProductKeyFormat -ProductKey $Cle | Should -BeFalse -Because $Motif
    }
}

Describe 'ConvertTo-OpMaskedText' {
    It 'masque la clé saisie avec et sans tirets, sans tenir compte de la casse' {
        $text = "PIDKEY=$fakeKey ; $($fakeKey.ToLowerInvariant()) ; BCDFGHJKMPQRTVWXY2346789B"
        $masked = ConvertTo-OpMaskedText -Text $text -ProductKey $fakeKey
        $masked | Should -Not -Match '(?i)BCDFG|6789B'
        $masked | Should -Be 'PIDKEY=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX ; XXXXX-XXXXX-XXXXX-XXXXX-XXXXX ; XXXXXXXXXXXXXXXXXXXXXXXXX'
    }

    It 'masque une clé de forme valide même sans clé saisie (motif générique)' {
        ConvertTo-OpMaskedText -Text 'clé ABCDE-12345-FGHIJ-67890-KLMNO' | Should -Be 'clé XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
    }

    It 'laisse intact un texte sans clé' {
        ConvertTo-OpMaskedText -Text 'Version 16.0.17932.21000, code 0' -ProductKey $fakeKey | Should -Be 'Version 16.0.17932.21000, code 0'
    }
}

Describe 'Protect-OpLogFile' {
    It 'masque toutes les formes de la clé dans un journal UTF-16 et le réécrit en UTF-16 avec sa marque' {
        $copy = Join-Path $TestDrive 'journal-utf16.log'
        Copy-Item -Path $fixture -Destination $copy
        Protect-OpLogFile -Path $copy -ProductKey $fakeKey | Should -Be 3
        $bytes = [IO.File]::ReadAllBytes($copy)
        ('{0:X2}{1:X2}' -f $bytes[0], $bytes[1]) | Should -Be 'FFFE'
        $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        $text | Should -Not -Match '(?i)BCDFG|HJKMP|6789B'
        $text | Should -Match 'Fichier de journal synthétique'
        $text | Should -Match 'Configuration terminée, code 0\.'
        ($text -split "`r`n").Count | Should -Be (([Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($fixture), 2, [IO.File]::ReadAllBytes($fixture).Length - 2)) -split "`r`n").Count
    }

    It 'masque un journal UTF-8 sans marque et le laisse sans marque' {
        $file = Join-Path $TestDrive 'journal-utf8.log'
        [IO.File]::WriteAllText($file, "PIDKEY=$fakeKey`r`nfin", (New-Object System.Text.UTF8Encoding $false))
        Protect-OpLogFile -Path $file -ProductKey $fakeKey | Should -Be 1
        $bytes = [IO.File]::ReadAllBytes($file)
        $bytes[0] | Should -Be ([byte][char]'P')
        [Text.Encoding]::UTF8.GetString($bytes) | Should -Be "PIDKEY=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`r`nfin"
    }

    It 'reconnaît un journal UTF-16 sans marque' {
        $file = Join-Path $TestDrive 'journal-utf16-sans-marque.log'
        [IO.File]::WriteAllText($file, "clé $fakeKey fin", (New-Object System.Text.UnicodeEncoding($false, $false)))
        Protect-OpLogFile -Path $file -ProductKey $fakeKey | Should -Be 1
        $bytes = [IO.File]::ReadAllBytes($file)
        [Text.Encoding]::Unicode.GetString($bytes) | Should -Be 'clé XXXXX-XXXXX-XXXXX-XXXXX-XXXXX fin'
    }

    It 'ne réécrit pas un journal sans clé' {
        $file = Join-Path $TestDrive 'propre.log'
        [IO.File]::WriteAllText($file, 'rien à masquer', (New-Object System.Text.UTF8Encoding $false))
        $before = (Get-Item $file).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        Protect-OpLogFile -Path $file -ProductKey $fakeKey | Should -Be 0
        (Get-Item $file).LastWriteTimeUtc | Should -Be $before
    }

    It 'respecte -WhatIf' {
        $copy = Join-Path $TestDrive 'whatif.log'
        Copy-Item -Path $fixture -Destination $copy
        Protect-OpLogFile -Path $copy -ProductKey $fakeKey -WhatIf | Out-Null
        [IO.File]::ReadAllBytes($copy).Length | Should -Be ([IO.File]::ReadAllBytes($fixture).Length)
        [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($copy)) | Should -Match 'BCDFG'
    }
}
