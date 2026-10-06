# Lancer-OffPatch.cmd (cahier des charges 8.1) : fichier ASCII, chemin avec espaces et accents, cmd 32 bits,
# demande d'élévation avec arguments conservés. La branche d'élévation est testée en mode d'essai
# (OFFPATCH_LAUNCHER_DRYRUN) : aucune demande UAC n'est jamais affichée. Le cas « racine d'un lecteur » et le
# lancement réellement élevé sont testés sur runner (tests/runner/Invoke-LauncherTest.ps1).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $launcher = Join-Path $root 'Lancer-OffPatch.cmd'
    $cmd64 = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $cmd32 = Join-Path $env:SystemRoot 'SysWOW64\cmd.exe'

    # Copie du lanceur dans Folder, avec un faux app\OffPatch.ps1 qui relève son chemin, ses arguments et son bitness.
    function Get-LauncherCopy([string]$Folder) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Folder 'app') | Out-Null
        Copy-Item -Path $launcher -Destination $Folder
        $fake = @'
$record = [ordered]@{ Path = $PSCommandPath; Args = @($args); Is64BitProcess = [Environment]::Is64BitProcess }
[IO.File]::WriteAllText($env:OFFPATCH_TEST_OUT, (ConvertTo-Json -InputObject $record -Compress), (New-Object Text.UTF8Encoding $false))
'@
        [IO.File]::WriteAllText((Join-Path $Folder 'app\OffPatch.ps1'), $fake, (New-Object Text.UTF8Encoding $true))
        Join-Path $Folder 'Lancer-OffPatch.cmd'
    }

    # Lance le .cmd par cmd.exe /c, avec une ligne de commande écrite à la main (règles de guillemets de cmd).
    function Invoke-Launcher([string]$Cmd, [string]$Path, [string]$Arguments, [hashtable]$Environment) {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $Cmd
        $info.Arguments = '/c ""' + $Path + '" ' + $Arguments + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        foreach ($k in $Environment.Keys) { $info.EnvironmentVariables[$k] = $Environment[$k] }
        $p = [System.Diagnostics.Process]::Start($info)
        if (-not $p.WaitForExit(60000)) { $p.Kill(); throw 'lanceur bloqué' }
        $p.ExitCode
    }
}

Describe 'Lancer-OffPatch.cmd' {
    It 'est en ASCII pur, avec des fins de ligne CRLF' {
        $bytes = [IO.File]::ReadAllBytes($launcher)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $text = [Text.Encoding]::ASCII.GetString($bytes)
        ([regex]::Matches($text, "(?<!`r)`n")).Count | Should -Be 0
    }

    It 'lance le script depuis un chemin avec espaces et accents, arguments conservés' {
        $folder = Join-Path $TestDrive 'Mises à jour Windows et Office'
        $copy = Get-LauncherCopy -Folder $folder
        $out = Join-Path $TestDrive 'direct.json'
        $code = Invoke-Launcher -Cmd $cmd64 -Path $copy -Arguments '-Resume "deux mots" été' -Environment @{ OFFPATCH_TEST_OUT = $out; OFFPATCH_LAUNCHER_DRYRUN = (Join-Path $TestDrive 'inutile.txt'); OFFPATCH_LAUNCHER_FORCE = 'direct' }
        $code | Should -Be 0
        $r = Get-Content -Path $out -Raw -Encoding UTF8 | ConvertFrom-Json
        $r.Path | Should -Be (Join-Path $folder 'app\OffPatch.ps1')
        @($r.Args) | Should -Be @('-Resume', 'deux mots', 'été')
        $r.Is64BitProcess | Should -BeTrue
    }

    It 'lance le PowerShell 64 bits depuis un cmd 32 bits (Sysnative)' -Skip:(-not (Test-Path (Join-Path $env:SystemRoot 'SysWOW64\cmd.exe'))) {
        $folder = Join-Path $TestDrive 'cmd32'
        $copy = Get-LauncherCopy -Folder $folder
        $out = Join-Path $TestDrive 'cmd32.json'
        Invoke-Launcher -Cmd $cmd32 -Path $copy -Arguments '-Resume' -Environment @{ OFFPATCH_TEST_OUT = $out; OFFPATCH_LAUNCHER_DRYRUN = (Join-Path $TestDrive 'inutile32.txt'); OFFPATCH_LAUNCHER_FORCE = 'direct' } | Should -Be 0
        (Get-Content -Path $out -Raw -Encoding UTF8 | ConvertFrom-Json).Is64BitProcess | Should -BeTrue
    }

    It 'demande l''élévation avec le PowerShell natif, le chemin du script et les arguments conservés' {
        $folder = Join-Path $TestDrive 'Élévation avec espaces'
        $copy = Get-LauncherCopy -Folder $folder
        $dry = Join-Path $TestDrive 'elevation.txt'
        Invoke-Launcher -Cmd $cmd64 -Path $copy -Arguments '-Resume "deux mots"' -Environment @{ OFFPATCH_LAUNCHER_DRYRUN = $dry; OFFPATCH_LAUNCHER_FORCE = 'elevate' } | Should -Be 0
        $lines = @(Get-Content -Path $dry -Encoding UTF8)
        $lines[0] | Should -Be (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $lines[1] | Should -Be ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $folder 'app\OffPatch.ps1') + '" -Resume "deux mots"')
    }

    It 'demande l''élévation par Sysnative depuis un cmd 32 bits' -Skip:(-not (Test-Path (Join-Path $env:SystemRoot 'SysWOW64\cmd.exe'))) {
        $folder = Join-Path $TestDrive 'elev32'
        $copy = Get-LauncherCopy -Folder $folder
        $dry = Join-Path $TestDrive 'elevation32.txt'
        Invoke-Launcher -Cmd $cmd32 -Path $copy -Arguments '' -Environment @{ OFFPATCH_LAUNCHER_DRYRUN = $dry; OFFPATCH_LAUNCHER_FORCE = 'elevate' } | Should -Be 0
        $lines = @(Get-Content -Path $dry -Encoding UTF8)
        $lines[0] | Should -Be (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe')
        $lines[1] | Should -Be ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $folder 'app\OffPatch.ps1') + '"')
    }

    It 'ignore OFFPATCH_LAUNCHER_FORCE sans le mode d''essai' {
        $text = Get-Content -Path $launcher -Raw
        $text | Should -Match 'if defined OFFPATCH_LAUNCHER_DRYRUN if /i "%OFFPATCH_LAUNCHER_FORCE%"=="elevate"'
        $text | Should -Match 'if defined OFFPATCH_LAUNCHER_DRYRUN if /i "%OFFPATCH_LAUNCHER_FORCE%"=="direct"'
    }
}
