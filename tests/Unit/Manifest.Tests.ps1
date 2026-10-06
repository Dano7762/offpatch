# Manifeste du dépôt (cahier des charges 7.2) : lecture, validation, écriture atomique. Fixture : manifeste valide
# (empreintes fictives) ; aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Test-OpManifest', 'Read-OpManifest', 'Save-OpManifest') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $fixture = Join-Path $root 'tests\Fixtures\manifest\manifest-valide.json'
    function Get-FreshManifest { Read-OpJsonFile -Path $fixture }
}

Describe 'Read-OpManifest' {
    It 'lit le manifeste de fixture sans anomalie' {
        $m = Read-OpManifest -Path $fixture
        @($m.items).Count | Should -Be 4
    }

    It 'renvoie un manifeste vide quand le dépôt est neuf' {
        $m = Read-OpManifest -Path (Join-Path $TestDrive 'absent\manifest.json')
        $m.schemaVersion | Should -Be 1
        @($m.items).Count | Should -Be 0
    }

    It 'refuse un manifeste illisible en nommant le fichier' {
        $bad = Join-Path $TestDrive 'casse.json'
        Set-Content -Path $bad -Value '{ "items": [' -Encoding UTF8
        { Read-OpManifest -Path $bad } | Should -Throw -ExpectedMessage '*casse.json*'
    }
}

Describe 'Test-OpManifest' {
    It 'signale <Attendu>' -TestCases @(
        @{ Attendu = 'un identifiant en double'; Alter = { param($m) $m.items[1].id = $m.items[0].id }; Message = '*en double*' }
        @{ Attendu = 'un SHA-256 invalide'; Alter = { param($m) $m.items[2].files[0].sha256 = 'abc' }; Message = '*sha256 invalide*' }
        @{ Attendu = 'un chemin qui sort du dépôt'; Alter = { param($m) $m.items[2].files[0].path = 'files/../../Windows/x.msu' }; Message = '*hors du dépôt*' }
        @{ Attendu = 'un chemin absolu'; Alter = { param($m) $m.items[2].files[0].path = 'C:\depot\x.msu' }; Message = '*absolu*' }
        @{ Attendu = 'un dossier qui ne porte pas le SHA-256'; Alter = { param($m) $m.items[2].files[0].path = 'files/' + ('9' * 64) + '/x.msu' }; Message = '*dossier nommé par le SHA-256*' }
        @{ Attendu = 'un prérequis inconnu'; Alter = { param($m) $m.items[1].prerequisites = @('win11-x64-checkpoint-KB0000000') }; Message = '*ni identifiant du manifeste ni code de catégorie*' }
        @{ Attendu = 'une cumulative sans baseBuilds'; Alter = { param($m) $m.items[1].baseBuilds = @() }; Message = '*baseBuilds est vide*' }
        @{ Attendu = 'une cible invalide'; Alter = { param($m) $m.items[1].target.arch = 'x86' }; Message = '*cible invalide*' }
        @{ Attendu = 'un ordre non entier'; Alter = { param($m) $m.items[1].order = 'premier' }; Message = '*order doit être un entier*' }
        @{ Attendu = 'une source Office sans langues'; Alter = { param($m) $m.items[3].languages = @() }; Message = '*languages est vide*' }
        @{ Attendu = 'un élément sans fichier'; Alter = { param($m) $m.items[2].files = @() }; Message = '*aucun fichier*' }
    ) {
        param($Attendu, $Alter, $Message)
        $m = Get-FreshManifest
        & $Alter $m
        $errors = @(Test-OpManifest -Manifest $m)
        $errors.Count | Should -BeGreaterThan 0 -Because "l'anomalie « $Attendu » doit être signalée"
        ($errors -join ' | ') | Should -BeLike $Message
    }

    It 'accepte une dépendance par code de catégorie' {
        $m = Get-FreshManifest
        $m.items[1].prerequisites = @('windows-checkpoint')
        @(Test-OpManifest -Manifest $m).Count | Should -Be 0
    }
}

Describe 'Save-OpManifest' {
    It 'écrit puis relit le même contenu, sans fichier temporaire restant' {
        $target = Join-Path $TestDrive 'depot1\manifest.json'
        Save-OpManifest -Manifest (Get-FreshManifest) -Path $target -ToolVersion '0.1.0'
        Test-Path ($target + '.tmp') | Should -BeFalse
        $back = Read-OpManifest -Path $target
        @($back.items).Count | Should -Be 4
        $back.items[1].resultingUbr | Should -Be 9457
        @($back.items[1].baseBuilds) | Should -Be @(26100, 26200, 26300)
        @($back.items[0].files).Count | Should -Be 1
        $back.generatedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }

    It 'remplace un manifeste existant' {
        $target = Join-Path $TestDrive 'depot2\manifest.json'
        Save-OpManifest -Manifest (Get-FreshManifest) -Path $target
        $m = Get-FreshManifest
        $m.items = @($m.items[0])
        Save-OpManifest -Manifest $m -Path $target
        @((Read-OpManifest -Path $target).items).Count | Should -Be 1
        Test-Path ($target + '.tmp') | Should -BeFalse
    }

    It 'n''écrit jamais un manifeste incohérent et laisse l''ancien intact' {
        $target = Join-Path $TestDrive 'depot3\manifest.json'
        Save-OpManifest -Manifest (Get-FreshManifest) -Path $target
        $before = Get-Content -Path $target -Raw -Encoding UTF8
        $m = Get-FreshManifest
        $m.items[0].files[0].sha256 = 'faux'
        { Save-OpManifest -Manifest $m -Path $target } | Should -Throw -ExpectedMessage '*non écrit*sha256*'
        Get-Content -Path $target -Raw -Encoding UTF8 | Should -Be $before
    }

    It 'écrit en UTF-8 sans marque' {
        $target = Join-Path $TestDrive 'depot4\manifest.json'
        Save-OpManifest -Manifest (Get-FreshManifest) -Path $target
        $bytes = [IO.File]::ReadAllBytes($target)
        $bytes[0] | Should -Be ([byte][char]'{')
    }

    It 'respecte -WhatIf' {
        $target = Join-Path $TestDrive 'depot5\manifest.json'
        Save-OpManifest -Manifest (Get-FreshManifest) -Path $target -WhatIf
        Test-Path $target | Should -BeFalse
    }
}
