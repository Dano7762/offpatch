# Règles transversales du socle (CLAUDE.md) vérifiées sur tout le module : nommage, CmdletBinding, ShouldProcess pour
# les fonctions qui modifient le système ou le dépôt, aide des fonctions publiques, syntaxe PowerShell 5.1, rien en dur.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleFolder = Join-Path $root 'app\module\OffPatch'
    $functionFiles = @(Get-ChildItem -Path (Join-Path $moduleFolder 'Private'), (Join-Path $moduleFolder 'Public') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName; Public = ($_.Directory.Name -eq 'Public') } })
    $shippedScripts = @(Get-ChildItem -Path (Join-Path $root 'app') -Recurse -Include '*.ps1', '*.psm1' -File | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $approvedVerbs = @(Get-Verb | ForEach-Object { $_.Verb })
    # Verbes qui modifient le système ou le dépôt : ShouldProcess obligatoire (Write-OpLog, journal, en est exempté).
    $stateChangingVerbs = 'Save', 'Set', 'Remove', 'New', 'Start', 'Stop', 'Unblock', 'Install', 'Uninstall', 'Update', 'Clear', 'Copy', 'Move', 'Rename', 'Protect'
    # Processus lancés : ShouldProcess obligatoire aussi.
    $processRunners = 'Invoke-OpProcess', 'Invoke-OpOfficeSetup'
    function Get-FunctionAst([string]$Path) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
    }
}

Describe 'Fonction <Name>' -ForEach $functionFiles {
    BeforeAll {
        $functions = @(Get-FunctionAst -Path $Path)
        $function = $functions | Select-Object -First 1
        $attributes = @($function.Body.ParamBlock.Attributes)
        $binding = $attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' } | Select-Object -First 1
    }

    It 'contient une seule fonction, du nom du fichier' {
        $functions.Count | Should -Be 1
        $function.Name | Should -Be $Name
    }

    It 'porte le préfixe Op et un verbe approuvé' {
        $verb, $noun = $Name -split '-', 2
        $approvedVerbs | Should -Contain $verb
        $noun | Should -Match '^Op[A-Z]'
    }

    It 'déclare [CmdletBinding()]' {
        $binding | Should -Not -BeNullOrEmpty
    }

    It 'déclare SupportsShouldProcess si elle modifie le système ou le dépôt' {
        $verb = ($Name -split '-', 2)[0]
        if ($stateChangingVerbs -contains $verb -or $processRunners -contains $Name) {
            @($binding.NamedArguments | Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' }).Count | Should -Be 1 -Because "$Name modifie le système ou le dépôt"
        }
    }

    It 'a une aide complète (.SYNOPSIS, .DESCRIPTION, .EXAMPLE) si elle est publique' -Skip:(-not $Public) {
        $help = $function.GetHelpContent()
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        @($help.Examples).Count | Should -BeGreaterThan 0
    }
}

Describe 'Script livré <Name>' -ForEach $shippedScripts {
    It 'n''utilise aucune syntaxe absente de Windows PowerShell 5.1' {
        $text = Get-Content -Path $Path -Raw -Encoding UTF8
        $text | Should -Not -Match '-AdditionalChildPath|-AsHashtable|-AsByteStream|ForEach-Object\s+-Parallel|\?\?=?'
    }

    It 'ne contient ni numéro de KB ni URL hors des points d''entrée du catalogue' {
        $text = Get-Content -Path $Path -Raw -Encoding UTF8
        $text | Should -Not -Match '\bKB\d{6,}\b'
        $urls = @([regex]::Matches($text, 'https?://[^\s''"<>)]+') | ForEach-Object { $_.Value } |
                Where-Object { $_ -notmatch '^https://www\.catalog\.update\.microsoft\.com/(Search|DownloadDialog)\.aspx' })
        $urls | Should -BeNullOrEmpty
    }
}

Describe 'Module OffPatch' {
    It 'se charge dans un PowerShell neuf, en StrictMode, sans erreur ni avertissement' {
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $manifest = Join-Path $root 'app\module\OffPatch\OffPatch.psd1'
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $command = "Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; Import-Module '$manifest' -WarningVariable w; if (`$w) { exit 3 }; (Get-Command -Module OffPatch).Name -join ','"
        $output = & $powershell -NoProfile -NonInteractive -Command $command
        $LASTEXITCODE | Should -Be 0
        "$output" | Should -Match 'Initialize-OpSession'
    }
}
