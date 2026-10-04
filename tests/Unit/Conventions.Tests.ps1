# Conventions du dépôt : encodage et syntaxe compatibles Windows PowerShell 5.1.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $scriptFiles = @(
        foreach ($folder in 'app', 'tests') {
            $path = Join-Path $root $folder
            if (Test-Path $path) {
                Get-ChildItem -Path $path -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
            }
        }
        Get-Item (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
    ) | ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) } }
}

Describe 'Fichier <Name>' -ForEach $scriptFiles {
    It 'est enregistré en UTF-8 avec BOM' {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bytes.Length | Should -BeGreaterThan 2
        ('{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]) | Should -Be 'EFBBBF'
    }

    It 'est analysé sans erreur de syntaxe par le moteur courant' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }
}
