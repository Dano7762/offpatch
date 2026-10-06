# Module OffPatch : manifeste valide, chargement de Public/ et Private/, export limité à Public/.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleFolder = Join-Path $root 'app\module\OffPatch'
}

Describe 'Manifeste du module' {
    It 'est valide et vise Windows PowerShell 5.1' {
        $manifest = Test-ModuleManifest -Path (Join-Path $moduleFolder 'OffPatch.psd1') -ErrorAction Stop
        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $manifest.RootModule | Should -Be 'OffPatch.psm1'
    }

    It 'déclare exactement les fonctions de Public/ dans FunctionsToExport' {
        $declared = @((Import-PowerShellDataFile -Path (Join-Path $moduleFolder 'OffPatch.psd1')).FunctionsToExport | Sort-Object)
        $files = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Public') -Filter '*.ps1' -File | ForEach-Object { $_.BaseName } | Sort-Object)
        ($declared -join ',') | Should -Be ($files -join ',')
    }
}

Describe 'Chargement du module' {
    BeforeAll {
        # Copie du module avec une fonction publique et une fonction interne de test, dans TestDrive.
        $copy = Join-Path $TestDrive 'OffPatch'
        Copy-Item -Path $moduleFolder -Destination $copy -Recurse
        Set-Content -Path (Join-Path $copy 'Public\Get-OpTestPublic.ps1') -Value 'function Get-OpTestPublic { Get-OpTestPrivate }' -Encoding UTF8
        Set-Content -Path (Join-Path $copy 'Private\Get-OpTestPrivate.ps1') -Value 'function Get-OpTestPrivate { ''interne'' }' -Encoding UTF8
        $manifestPath = Join-Path $copy 'OffPatch.psd1'
        $text = [System.IO.File]::ReadAllText($manifestPath) -replace 'FunctionsToExport\s*=\s*@\([^)]*\)', 'FunctionsToExport = @(''Get-OpTestPublic'')'
        [System.IO.File]::WriteAllText($manifestPath, $text, (New-Object System.Text.UTF8Encoding $true))
        $module = Import-Module -Name (Join-Path $copy 'OffPatch.psd1') -Force -PassThru -ErrorAction Stop
    }
    AfterAll {
        Remove-Module -Name OffPatch -Force -ErrorAction SilentlyContinue
    }

    It 'exporte les fonctions de Public/ et elles appellent celles de Private/' {
        $module.ExportedFunctions.Keys | Should -Contain 'Get-OpTestPublic'
        Get-OpTestPublic | Should -Be 'interne'
    }

    It 'n''exporte pas les fonctions de Private/' {
        $module.ExportedFunctions.Keys | Should -Not -Contain 'Get-OpTestPrivate'
        $module.ExportedFunctions.Keys | Should -Not -Contain 'Find-OpCatalogUpdate'
    }

    It 'nomme le fichier en cause quand une fonction ne se charge pas' {
        $broken = Join-Path $TestDrive 'OffPatchCasse'
        Copy-Item -Path $moduleFolder -Destination $broken -Recurse
        Set-Content -Path (Join-Path $broken 'Private\Get-OpCasse.ps1') -Value 'throw ''défaut simulé''' -Encoding UTF8
        { Import-Module -Name (Join-Path $broken 'OffPatch.psd1') -Force -ErrorAction Stop } | Should -Throw -ExpectedMessage '*Get-OpCasse.ps1*'
    }
}
