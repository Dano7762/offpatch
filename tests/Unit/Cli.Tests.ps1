# OffPatch-Cli.ps1 : chargement, journal, configuration, actions Plan, InstallStep et Report, codes de sortie, aucune clé.
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

    # Plan et Report sont en lecture seule sur le PC (relevé, détection) ; le rapport s'écrit dans la copie de l'outil.
    It 'Plan ouvre le journal de session et affiche contrôles et plan, dépôt vide (code 0)' {
        $tool = Get-ToolCopy
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'Plan')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        $r.Output | Should -Match 'Contr.les pr.alables'
        $r.Output | Should -Match 'MissingFromDepot'
        @(Get-ChildItem -Path (Join-Path $tool 'ProgramData\OffPatch\logs') -Filter 'session_*.log').Count | Should -Be 1
    }

    It 'InstallStep sort en erreur (code 1) sans -StepId ou sur une étape absente du plan' {
        $tool = Get-ToolCopy
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'InstallStep')
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'StepId est obligatoire'
        (Invoke-Cli -Tool $tool -Arguments @('-Action', 'InstallStep', '-StepId', 'inexistante')).ExitCode | Should -Be 1
    }

    It 'Report écrit le rapport dans rapports\ et sa copie dans ProgramData (code 0)' {
        $tool = Get-ToolCopy
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'Report')
        $r.ExitCode | Should -Be 0 -Because $r.Output
        @(Get-ChildItem -Path (Join-Path $tool 'rapports') -Filter '*.html').Count | Should -Be 1
        @(Get-ChildItem -Path (Join-Path $tool 'ProgramData\OffPatch\logs') -Filter '*.html').Count | Should -Be 1
    }

    # DepotUpdate interroge le catalogue puis télécharge : testé sans réseau dans DepotPlan.Tests.ps1 et
    # DepotUpdate.Tests.ps1, et en ligne par le contrat. Ici, configuration invalide : arrêt avant tout accès réseau.
    It 'ouvre le journal du dépôt pour DepotUpdate, puis s''arrête sur une configuration invalide (code 1)' {
        $tool = Get-ToolCopy
        $settingsPath = Join-Path $tool 'config\settings.json'
        $text = [IO.File]::ReadAllText($settingsPath) -replace '"maxAutoReboots": 5', '"maxAutoReboots": 0'
        [IO.File]::WriteAllText($settingsPath, $text, (New-Object System.Text.UTF8Encoding $false))
        $r = Invoke-Cli -Tool $tool -Arguments @('-Action', 'DepotUpdate')
        $r.ExitCode | Should -Be 1
        Test-Path -Path (Join-Path $tool 'depot') | Should -BeFalse
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
