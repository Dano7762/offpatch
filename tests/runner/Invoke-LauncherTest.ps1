<#
.SYNOPSIS
    Essai sur un runner GitHub : Lancer-OffPatch.cmd à la racine d'un lecteur, sous un chemin accentué, depuis un cmd
    64 bits et 32 bits, dans une session déjà élevée.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système (lecteur subst, dossier à la racine
    de C:) : ne jamais l'exécuter ailleurs. Pour chaque emplacement (racine d'un lecteur créé par subst, R:\ ; dossier
    « C:\Mises à jour Windows et Office ») et chaque cmd (System32 64 bits, SysWOW64 32 bits s'il existe) :
      - lancement réel (session du runner déjà élevée : branche directe) avec des arguments à espaces et accents ; un
        faux app\OffPatch.ps1 relève son chemin, ses arguments et son bitness ;
      - mode d'essai de la branche d'élévation (OFFPATCH_LAUNCHER_DRYRUN) : commande d'élévation construite, dont le
        chemin du script, vérifiée (piège du \" final à la racine d'un lecteur).

.EXAMPLE
    .\Invoke-LauncherTest.ps1 -OutputDirectory $env:RUNNER_TEMP\launcher-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $toolRoot 'Lancer-OffPatch.cmd'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Lancer-OffPatch.cmd ($env:PROCESSOR_ARCHITECTURE, session administrateur : $($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))")
$lines.Add('')
$lines.Add('| Emplacement | cmd | Branche | Résultat | Détail |')
$lines.Add('|---|---|---|---|---|')
$failures = 0

$fake = @'
$record = [ordered]@{ Path = $PSCommandPath; Args = @($args); Is64BitProcess = [Environment]::Is64BitProcess }
[IO.File]::WriteAllText($env:OFFPATCH_TEST_OUT, (ConvertTo-Json -InputObject $record -Compress), (New-Object Text.UTF8Encoding $false))
'@

function Install-LauncherCopy([string]$Folder) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Folder 'app') | Out-Null
    Copy-Item -Path $launcher -Destination $Folder -Force
    [IO.File]::WriteAllText((Join-Path $Folder 'app\OffPatch.ps1'), $fake, (New-Object Text.UTF8Encoding $true))
}

function Invoke-Launcher([string]$Cmd, [string]$Path, [string]$Arguments, [hashtable]$Environment) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Cmd
    $info.Arguments = '/c ""' + $Path + '" ' + $Arguments + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    foreach ($k in $Environment.Keys) { $info.EnvironmentVariables[$k] = $Environment[$k] }
    $p = [System.Diagnostics.Process]::Start($info)
    if (-not $p.WaitForExit(120000)) { $p.Kill(); return 'bloqué' }
    $p.ExitCode
}

$substFolder = Join-Path $env:RUNNER_TEMP 'racine-lecteur'
$accentFolder = 'C:\Mises à jour Windows et Office'
$cmds = New-Object System.Collections.Generic.List[object]
$cmds.Add([pscustomobject]@{ Label = '64 bits'; Path = (Join-Path $env:SystemRoot 'System32\cmd.exe'); Tag = '64' })
$cmd32 = Join-Path $env:SystemRoot 'SysWOW64\cmd.exe'
if (Test-Path $cmd32) { $cmds.Add([pscustomobject]@{ Label = '32 bits'; Path = $cmd32; Tag = '32' }) }
$expectedArgs = @('-Resume', 'deux mots', 'été')

try {
    if (-not $PSCmdlet.ShouldProcess('R:', 'subst et dossiers d''essai')) { return }
    Install-LauncherCopy -Folder $substFolder
    & subst.exe R: $substFolder
    if ($LASTEXITCODE -ne 0) { throw "subst a échoué ($LASTEXITCODE)" }
    Install-LauncherCopy -Folder $accentFolder

    foreach ($place in @(@('racine du lecteur R:\', 'R:\'), @('C:\Mises à jour Windows et Office\', ($accentFolder + '\')))) {
        $folder = $place[1]
        $copy = $folder + 'Lancer-OffPatch.cmd'
        $expectedScript = $folder + 'app\OffPatch.ps1'
        foreach ($c in $cmds) {
            # Lancement réel, branche directe (session déjà élevée)
            $out = Join-Path $OutputDirectory ("reel-{0}-{1}.json" -f $place[0].Length, $c.Tag)
            $code = Invoke-Launcher -Cmd $c.Path -Path $copy -Arguments '-Resume "deux mots" été' -Environment @{ OFFPATCH_TEST_OUT = $out }
            $ok = $false
            $detail = "code $code"
            if (Test-Path $out) {
                $r = Get-Content -Path $out -Raw -Encoding UTF8 | ConvertFrom-Json
                $ok = ($r.Path -eq $expectedScript) -and ((@($r.Args) -join '|') -eq ($expectedArgs -join '|')) -and $r.Is64BitProcess
                $detail = "code $code ; script $($r.Path) ; arguments $(@($r.Args) -join ' / ') ; 64 bits $($r.Is64BitProcess)"
            }
            if (-not $ok) { $failures++ }
            $lines.Add("| $($place[0]) | $($c.Label) | directe (réelle) | $(if ($ok) { 'conforme' } else { 'ÉCHEC' }) | $detail |")

            # Branche d'élévation en mode d'essai : commande construite
            $dry = Join-Path $OutputDirectory ("elevation-{0}-{1}.txt" -f $place[0].Length, $c.Tag)
            $code = Invoke-Launcher -Cmd $c.Path -Path $copy -Arguments '-Resume "deux mots"' -Environment @{ OFFPATCH_LAUNCHER_DRYRUN = $dry; OFFPATCH_LAUNCHER_FORCE = 'elevate' }
            $ok = $false
            $detail = "code $code"
            if (Test-Path $dry) {
                $l = @(Get-Content -Path $dry -Encoding UTF8)
                $expectedPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                if ($c.Tag -eq '32') { $expectedPs = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }
                $ok = ($l[0] -eq $expectedPs) -and ($l[1] -eq ('-NoProfile -ExecutionPolicy Bypass -File "' + $expectedScript + '" -Resume "deux mots"'))
                $detail = "code $code ; $($l[0]) $($l[1])"
            }
            if (-not $ok) { $failures++ }
            $lines.Add("| $($place[0]) | $($c.Label) | élévation (essai) | $(if ($ok) { 'conforme' } else { 'ÉCHEC' }) | $($detail -replace '\|', '/') |")
        }
    }
} finally {
    & subst.exe R: /D 2>$null | Out-Null
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
if ($failures -gt 0) { throw "$failures cas non conforme(s) : voir le résumé." }
