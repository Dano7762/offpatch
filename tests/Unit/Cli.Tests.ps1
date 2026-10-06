# OffPatch-Cli.ps1 (squelette, phase 1) : chargement, journal, configuration, codes de sortie, aucun paramètre de clé.
# La CLI est lancée dans un PowerShell enfant sur une copie de l'outil (TestDrive), ProgramData redirigé dans TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $cli = Join-Path $root 'app\OffPatch-Cli.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    function Get-ToolCopy {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path $copy | Out-Null
        Copy-Item -Path (Join-Path $root 'app') -Destination $copy -Recurse
        Copy-Item -Path (Join-Path $root 'config') -Destination $copy -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $copy
        $copy
    }

    function Invoke-Cli([string]$Tool, [string[]]$Arguments) {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $powershell
        $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $Tool 'app\OffPatch-Cli.ps1') + '" ' + ($Arguments -join ' ')
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.CreateNoWindow = $true
        $info.EnvironmentVariables['ProgramData'] = Join-Path $Tool 'ProgramData'
        $p = [System.Diagnostics.Process]::Start($info)
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'CLI bloquée' }
        [pscustomobject]@{ ExitCode = $p.ExitCode; Output = $out.Result + $err.Result }
    }
}

Describe 'OffPatch-Cli.ps1' {
    It 'n''a aucun paramètre de clé de produit, de profil ou de retrait' {
        $parameters = (Get-Command -Name $cli).Parameters.Keys
        @($parameters | Where-Object { $_ -match '(?i)key|cle\b|^pid|pidkey|profil|remove|retrait|edition' }).Count | Should -Be 0
    }

    It 'ouvre le journal de session et signale une action pas encore disponible (code 2)' {
        $tool = Get-ToolCopy
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'Plan')
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'Plan pas encore disponible'
        @(Get-ChildItem -Path (Join-Path $tool 'ProgramData\OffPatch\logs') -Filter 'session_*.log').Count | Should -Be 1
    }

    It 'ouvre le journal du dépôt pour DepotUpdate -ListOnly' {
        $tool = Get-ToolCopy
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'DepotUpdate', '-ListOnly')
        $r.ExitCode | Should -Be 2
        $r.Output | Should -Match 'DepotUpdate \(-ListOnly\)'
        $log = @(Get-ChildItem -Path (Join-Path $tool 'logs') -Filter 'depot_*.log')
        $log.Count | Should -Be 1
        Get-Content -Path $log[0].FullName -Raw -Encoding UTF8 | Should -Match '\[INFO\] OffPatch, opération Depot'
    }

    It 'sort en erreur (code 1) sur une configuration invalide, anomalies au journal' {
        $tool = Get-ToolCopy
        $settingsPath = Join-Path $tool 'config\settings.json'
        $text = [IO.File]::ReadAllText($settingsPath) -replace '"maxAutoReboots": 5', '"maxAutoReboots": 0'
        [IO.File]::WriteAllText($settingsPath, $text, (New-Object System.Text.UTF8Encoding $false))
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'Plan')
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'maxAutoReboots'
        $log = @(Get-ChildItem -Path (Join-Path $tool 'ProgramData\OffPatch\logs') -Filter 'session_*.log')
        Get-Content -Path $log[0].FullName -Raw -Encoding UTF8 | Should -Match '\[ERROR\] Configuration invalide'
    }

    It 'refuse une action inconnue' {
        $tool = Get-ToolCopy
        (Invoke-Cli -Tool $tool -Arguments @('-Action', 'InstallOffice')).ExitCode | Should -Not -Be 0
    }
}
