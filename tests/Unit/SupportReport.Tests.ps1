# Rapatriement des rapports déjà présents sur le support (cahier des charges 7.4, étape 4). Poste et support
# factices dans TestDrive : aucun rapport écrasé, rien de supprimé sur le support.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fonctions factices du module : leurs paramètres servent aux filtres des simulacres.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath') { . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1") }
    . (Join-Path $repo 'app\module\OffPatch\Public\Copy-OpSupportReport.ps1')
    function Write-OpLog { param($Message, $Level) }

    function Initialize-TestPair {
        $script:station = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:support = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:station 'rapports'), (Join-Path $script:support 'rapports') | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:support 'offpatch.root'), '')
    }
    function Write-TestFile([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text) }
}

Describe 'Copy-OpSupportReport' {
    BeforeEach { Initialize-TestPair }

    It 'copie les rapports du support dans rapports\ du poste sans rien retirer du support' {
        Write-TestFile (Join-Path $script:support 'rapports\2026-10-21_PC1_ABC.html') 'un'
        Write-TestFile (Join-Path $script:support 'rapports\notes.txt') 'pas un rapport'
        $r = @(Copy-OpSupportReport -Destination $script:support -Root $script:station)
        $r.Count | Should -Be 1
        $r[0].Status | Should -Be 'Copied'
        [IO.File]::ReadAllText((Join-Path $script:station 'rapports\2026-10-21_PC1_ABC.html')) | Should -Be 'un'
        Test-Path (Join-Path $script:support 'rapports\2026-10-21_PC1_ABC.html') | Should -BeTrue
        Test-Path (Join-Path $script:station 'rapports\notes.txt') | Should -BeFalse
        @(Get-ChildItem (Join-Path $script:station 'rapports') -Filter '*.tmp').Count | Should -Be 0
    }

    It 'ignore un rapport identique déjà rapatrié, même sous un nom suffixé' {
        Write-TestFile (Join-Path $script:support 'rapports\R.html') 'deux'
        Write-TestFile (Join-Path $script:station 'rapports\R.html') 'autre'
        Write-TestFile (Join-Path $script:station 'rapports\R_2.html') 'deux'
        $r = @(Copy-OpSupportReport -Destination $script:support -Root $script:station)
        $r[0].Status | Should -Be 'AlreadyPresent'
        @(Get-ChildItem (Join-Path $script:station 'rapports')).Count | Should -Be 2
    }

    It 'suffixe un rapport de même nom mais de contenu différent, sans écraser celui du poste' {
        Write-TestFile (Join-Path $script:support 'rapports\R.html') 'nouveau'
        Write-TestFile (Join-Path $script:station 'rapports\R.html') 'ancien'
        $r = @(Copy-OpSupportReport -Destination $script:support -Root $script:station)
        $r[0].Path | Should -Be (Join-Path $script:station 'rapports\R_2.html')
        [IO.File]::ReadAllText((Join-Path $script:station 'rapports\R.html')) | Should -Be 'ancien'
        [IO.File]::ReadAllText((Join-Path $script:station 'rapports\R_2.html')) | Should -Be 'nouveau'
    }

    It 'crée rapports\ sur le poste s''il manque' {
        Remove-Item (Join-Path $script:station 'rapports')
        Write-TestFile (Join-Path $script:support 'rapports\R.html') 'x'
        @(Copy-OpSupportReport -Destination $script:support -Root $script:station)[0].Status | Should -Be 'Copied'
        Test-Path (Join-Path $script:station 'rapports\R.html') | Should -BeTrue
    }

    It 'ne fait rien sur un support sans OffPatch ou sans dossier rapports' {
        Write-TestFile (Join-Path $script:support 'rapports\R.html') 'x'
        Remove-Item (Join-Path $script:support 'offpatch.root')
        @(Copy-OpSupportReport -Destination $script:support -Root $script:station).Count | Should -Be 0
        [IO.File]::WriteAllText((Join-Path $script:support 'offpatch.root'), '')
        Remove-Item (Join-Path $script:support 'rapports') -Recurse
        @(Copy-OpSupportReport -Destination $script:support -Root $script:station).Count | Should -Be 0
        @(Get-ChildItem (Join-Path $script:station 'rapports')).Count | Should -Be 0
    }

    It 'respecte -WhatIf' {
        Write-TestFile (Join-Path $script:support 'rapports\R.html') 'x'
        Copy-OpSupportReport -Destination $script:support -Root $script:station -WhatIf
        Test-Path (Join-Path $script:station 'rapports\R.html') | Should -BeFalse
    }

    It 'journalise un rapport illisible et continue avec les autres' {
        Write-TestFile (Join-Path $script:support 'rapports\A.html') 'a'
        Write-TestFile (Join-Path $script:support 'rapports\B.html') 'b'
        Mock Get-FileHash { throw 'lecture impossible' } -ParameterFilter { $LiteralPath -like '*A.html' }
        Mock Write-OpLog {}
        $r = @(Copy-OpSupportReport -Destination $script:support -Root $script:station)
        ($r | Where-Object { $_.Source -like '*A.html' }).Status | Should -Be 'Failed'
        ($r | Where-Object { $_.Source -like '*B.html' }).Status | Should -Be 'Copied'
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' } -Times 1 -Exactly
    }
}
