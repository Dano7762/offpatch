# Racine de l'outil et emplacements connus (cahier des charges, section 5). Arborescences simulées dans TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Get-OpRoot.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\Get-OpPath.ps1')
}

Describe 'Get-OpRoot' {
    BeforeAll {
        $support = Join-Path $TestDrive 'Support'
        $deep = Join-Path $support 'app\module\OffPatch\Private'
        New-Item -ItemType Directory -Force -Path $deep | Out-Null
        Set-Content -Path (Join-Path $support 'offpatch.root') -Value '{}' -Encoding UTF8
    }

    It 'remonte jusqu''au dossier qui contient offpatch.root' {
        Get-OpRoot -StartPath $deep | Should -Be $support
    }

    It 'renvoie le dossier de départ s''il contient le marqueur' {
        Get-OpRoot -StartPath $support | Should -Be $support
    }

    It 'lève une erreur explicite sans marqueur' {
        $orphan = Join-Path $TestDrive 'SansMarqueur\sous'
        New-Item -ItemType Directory -Force -Path $orphan | Out-Null
        { Get-OpRoot -StartPath $orphan } | Should -Throw -ExpectedMessage '*offpatch.root*'
    }

    It 'trouve la racine du dépôt de travail depuis le dossier du module' {
        Get-OpRoot -StartPath (Join-Path $root 'app\module\OffPatch\Private') | Should -Be $root
    }
}

Describe 'Get-OpPath' {
    BeforeAll {
        $support = Join-Path $TestDrive 'Cle'
        New-Item -ItemType Directory -Force -Path $support | Out-Null
        Set-Content -Path (Join-Path $support 'offpatch.root') -Value '{}' -Encoding UTF8
        $savedProgramData = $env:ProgramData
    }
    AfterAll { $env:ProgramData = $savedProgramData }

    It 'calcule les emplacements du support à partir de la racine' {
        Get-OpPath -Name Root -Root $support | Should -Be $support
        Get-OpPath -Name Manifest -Root $support | Should -Be (Join-Path $support 'depot\manifest.json')
        Get-OpPath -Name DepotTemp -Root $support | Should -Be (Join-Path $support 'depot\.tmp')
        Get-OpPath -Name Odt -Root $support | Should -Be (Join-Path $support 'tools\odt')
        Get-OpPath -Name Reports -Root $support | Should -Be (Join-Path $support 'rapports')
    }

    It 'calcule les emplacements du PC client à partir de ProgramData, sans lettre de lecteur en dur' {
        $env:ProgramData = Join-Path $TestDrive 'PD'
        Get-OpPath -Name ProgramData | Should -Be (Join-Path $TestDrive 'PD\OffPatch')
        Get-OpPath -Name State | Should -Be (Join-Path $TestDrive 'PD\OffPatch\state.json')
        Get-OpPath -Name ClientTemp | Should -Be (Join-Path $TestDrive 'PD\OffPatch\temp')
    }

    It 'ne crée aucun dossier' {
        $null = Get-OpPath -Name DepotFiles -Root $support
        Test-Path -Path (Join-Path $support 'depot') | Should -BeFalse
    }
}
