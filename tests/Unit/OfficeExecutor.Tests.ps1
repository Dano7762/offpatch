# Exécuteur Office (cahier des charges 8.5, R-08, R-10) : mise à jour seulement, XML tiré de update.xml.template,
# contrôles avant l'ODT, jugement par la version relue. Registre Click-to-Run (Get-OpOfficeInstallation) et ODT
# (Invoke-OpOfficeSetup) simulés ; ProgramData redirigé vers TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpRoot', 'Get-OpPath', 'Invoke-OpProcess', 'Invoke-OpOfficeSetup', 'Get-OpFileVersion', 'Get-OpOfficeInstallation', 'Test-OpItemFileHash', 'Install-OpOfficeUpdate') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    $script:sources = (Get-Content -LiteralPath (Join-Path $repo 'config\office\sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    $script:template = Join-Path $repo 'config\office\update.xml.template'

    # Racine d'outil simulée : modèle, source Current au dépôt (deux fichiers), setup.exe factice.
    function Get-OfficeScene([switch]$Corrupt) {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path "$root\config\office", "$root\tools\odt", "$root\depot\office\current\Office\Data" | Out-Null
        Copy-Item -LiteralPath $script:template -Destination "$root\config\office\update.xml.template"
        Set-Content -Path "$root\tools\odt\setup.exe" -Value 'factice' -Encoding UTF8
        $files = foreach ($n in 'v64.cab', 'Office\Data\stream.x64.x-none.dat') {
            $p = Join-Path "$root\depot\office\current" $n
            Set-Content -Path $p -Value "contenu $n" -Encoding UTF8
            [pscustomobject]@{ path = "office/current/$($n -replace '\\', '/')"; sha256 = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant(); size = 1 }
        }
        if ($Corrupt) { Add-Content -Path "$root\depot\office\current\v64.cab" -Value 'altéré' }
        [pscustomobject]@{
            Root  = $root
            Logs  = Join-Path $root 'session'
            Item  = [pscustomobject]@{ id = 'office-current-16.0.20430.20140'; category = 'office-source'; channel = 'Current'; version = '16.0.20430.20140'; languages = @('fr-fr', 'en-us'); folder = 'office/current'; files = @($files) }
            Config = [pscustomobject]@{ Settings = [pscustomobject]@{ client = [pscustomobject]@{ odtTimeoutMinutes = 30 } }; OfficeSources = $script:sources }
        }
    }
    function Get-Office([string]$Version = '16.0.20430.20092', [string[]]$Languages = @('fr-fr'), [string]$Channel = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60', [string]$Platform = 'x64') {
        [pscustomobject]@{ Products = @('O365HomePremRetail'); Languages = $Languages; Platform = $Platform; ChannelId = $Channel; Version = $Version }
    }
    # Relevés successifs d'Office (avant, après) et résultat de l'ODT ; le XML passé à l'ODT est gardé.
    function Use-OfficeRun([object[]]$Office, [hashtable]$Run = @{ ExitCode = 0; TimedOut = $false }) {
        $script:offices = $Office
        $script:read = 0
        $script:run = $Run
        $script:xml = $null
        Mock Get-OpOfficeInstallation { $o = $script:offices[[math]::Min($script:read, $script:offices.Count - 1)]; $script:read++; $o }
        Mock Invoke-OpOfficeSetup {
            $script:xml = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
            Remove-Item -LiteralPath $ConfigPath
            [pscustomobject]@{ ExitCode = $script:run.ExitCode; TimedOut = $script:run.TimedOut; StdOut = ''; StdErr = ''; Seconds = 1; OdtLogs = @('PC-20261017-1000.log') }
        }
    }
}

Describe 'Install-OpOfficeUpdate' {
    BeforeEach {
        Mock Write-OpLog {}
        $script:clientTemp = Join-Path $TestDrive "programdata-temp-$([guid]::NewGuid())"
        Mock Get-OpPath { $script:clientTemp } -ParameterFilter { $Name -eq 'ClientTemp' }
    }

    It 'met à jour depuis la source locale avec les produits et langues installés, et juge sur la version' {
        $s = Get-OfficeScene
        Use-OfficeRun @((Get-Office -Languages 'fr-fr', 'en-us'), (Get-Office '16.0.20430.20140' -Languages 'fr-fr', 'en-us'))
        $r = Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config
        $r.State | Should -Be 'UpToDate'
        $r.Before | Should -Be '16.0.20430.20092'
        $r.Installed | Should -Be '16.0.20430.20140'
        $r.OdtLogs | Should -Be 'PC-20261017-1000.log'
        $x = [xml]$script:xml
        $x.Configuration.Add.SourcePath | Should -Be (Join-Path $s.Root 'depot\office\current')
        $x.Configuration.Add.Channel | Should -Be 'Current'
        $x.Configuration.Add.AllowCdnFallback | Should -Be 'FALSE'
        $x.Configuration.Add.Product.ID | Should -Be 'O365HomePremRetail'
        @($x.Configuration.Add.Product.Language.ID) | Should -Be @('fr-fr', 'en-us')
        $script:xml | Should -Not -Match 'PIDKEY|<Remove'
        Should -Invoke Invoke-OpOfficeSetup -Times 1 -Exactly -ParameterFilter { $Mode -eq 'configure' -and $TimeoutMinutes -eq 30 -and $SessionLogDirectory -eq $s.Logs -and $ConfigPath -like "$script:clientTemp\*" }
    }

    It 'ne lance pas l''ODT et rend NotApplicable : <Cas>' -TestCases @(
        @{ Cas = 'aucun Office Click-to-Run'; Office = $null; Pattern = 'Aucun Office' }
        @{ Cas = 'Office 32 bits'; Office = @{ Platform = 'x86' }; Pattern = '32 bits' }
        @{ Cas = 'canal absent du dépôt'; Office = @{ Channel = '7983bac0-e531-40cf-be00-fd24fe66619c' }; Pattern = 'Canal absent' }
        @{ Cas = 'langue absente de la source'; Office = @{ Languages = @('fr-fr', 'de-de') }; Pattern = 'de-de' }
    ) {
        param($Cas, $Office, $Pattern)
        $s = Get-OfficeScene
        $o = $null
        if ($Office) { $o = Get-Office @Office }
        Use-OfficeRun @(, $o)
        $r = Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config
        $r.State | Should -Be 'NotApplicable' -Because $Cas
        $r.Reason | Should -Match $Pattern
        Should -Invoke Invoke-OpOfficeSetup -Times 0 -Exactly
    }

    It 'ne lance pas l''ODT si un fichier de la source a changé, et liste le fichier' {
        $s = Get-OfficeScene -Corrupt
        Use-OfficeRun @(, (Get-Office))
        $r = Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config
        $r.State | Should -Be 'Error'
        $r.Reason | Should -Match 'v64\.cab'
        Should -Invoke Invoke-OpOfficeSetup -Times 0 -Exactly
    }

    It 'est en erreur avec <Cas>' -TestCases @(
        @{ Cas = 'le code de l''ODT'; Run = @{ ExitCode = 17002; TimedOut = $false }; After = '16.0.20430.20092'; Pattern = '17002' }
        @{ Cas = 'le délai dépassé'; Run = @{ ExitCode = $null; TimedOut = $true }; After = '16.0.20430.20092'; Pattern = 'Délai dépassé \(30 min\)' }
        @{ Cas = 'un code 0 sans la nouvelle version'; Run = @{ ExitCode = 0; TimedOut = $false }; After = '16.0.20430.20092'; Pattern = 'sans atteindre' }
    ) {
        param($Cas, $Run, $After, $Pattern)
        $s = Get-OfficeScene
        Use-OfficeRun @((Get-Office), (Get-Office $After)) $Run
        $r = Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config
        $r.State | Should -Be 'Error' -Because $Cas
        $r.Reason | Should -Match $Pattern
        $r.Installed | Should -Be $After
    }

    It 'respecte -WhatIf' {
        $s = Get-OfficeScene
        Use-OfficeRun @(, (Get-Office))
        Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Invoke-OpOfficeSetup -Times 0 -Exactly
        Test-Path $script:clientTemp | Should -BeFalse
    }

    It 'refuse une autre catégorie' {
        $s = Get-OfficeScene
        $s.Item.category = 'defender'
        { Install-OpOfficeUpdate -Item $s.Item -LogDirectory $s.Logs -Root $s.Root -Configuration $s.Config } | Should -Throw '*non prise en charge*'
    }
}
