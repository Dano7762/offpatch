<#
.SYNOPSIS
    Amorce de reprise après redémarrage : retrouve le support d'OffPatch et relance l'interface avec -Resume.

.DESCRIPTION
    Cahier des charges 8.6. Copié dans ProgramData\OffPatch avant un redémarrage et lancé par la tâche planifiée
    OffPatch-Reprise à l'ouverture de session. Il ne dépend pas du module : le support peut être absent.
      1. Lit ProgramData\OffPatch\state.json : numéro de série du volume du support et chemin relatif de la racine.
      2. Cherche, sur tous les lecteurs (Win32_LogicalDisk), celui dont le numéro de série correspond et qui porte
         offpatch.root à ce chemin : la lettre peut avoir changé depuis le redémarrage. Si l'état ne connaît pas
         le numéro de série (illisible au début de la session), le marqueur seul suffit, avec une mention au journal.
      3. Relance <racine>\app\OffPatch.ps1 -Resume avec le PowerShell natif du système (Sysnative depuis un
         processus 32 bits sur Windows 64 bits, comme Lancer-OffPatch.cmd), sans attendre sa fin.
    Journal : ProgramData\OffPatch\logs\resume_AAAA-MM-JJ_HHMMSS.log.
    Codes de sortie : 0 interface relancée, 1 état de session absent ou illisible, 2 support introuvable.

.PARAMETER StatePath
    Chemin de state.json ; par défaut ProgramData\OffPatch\state.json.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\OffPatch\resume.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StatePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = Join-Path $env:ProgramData 'OffPatch'
if (-not $StatePath) { $StatePath = Join-Path $base 'state.json' }
$logPath = Join-Path (Join-Path $base 'logs') ('resume_{0:yyyy-MM-dd_HHmmss}.log' -f (Get-Date))

function Write-ResumeLog([string]$Message, [string]$Level = 'INFO') {
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Verbose $line
    if ($WhatIfPreference) { return }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Path $logPath -Parent) | Out-Null
        [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    } catch {
        Write-Warning "Journal de reprise inaccessible : $line"
    }
}

# Racine du support : lecteur au bon numéro de série (s'il est connu) portant offpatch.root au chemin relatif.
function Find-ResumeSupport([string]$Serial, [string]$RelativeRoot) {
    foreach ($disk in @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop)) {
        if (-not $disk.DeviceID) { continue }
        if ($Serial -and [string]$disk.VolumeSerialNumber -ne $Serial) { continue }
        $root = ([string]$disk.DeviceID).TrimEnd('\') + '\'
        if ($RelativeRoot -and $RelativeRoot -ne '.') { $root = Join-Path $root $RelativeRoot }
        if (Test-Path -LiteralPath (Join-Path $root 'offpatch.root') -PathType Leaf) { return $root }
    }
    $null
}

try {
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $serial = [string]$state.support.volumeSerial
    $relative = [string]$state.support.relativeRoot
} catch {
    Write-ResumeLog "État de session absent ou illisible ($StatePath) : $($_.Exception.Message)" 'ERROR'
    exit 1
}
if (-not $serial) { Write-ResumeLog 'Numéro de série du support inconnu dans state.json : recherche par le seul marqueur offpatch.root.' 'WARN' }

$root = Find-ResumeSupport $serial $relative
if (-not $root) {
    Write-ResumeLog "Support introuvable (volume $(if ($serial) { $serial } else { 'inconnu' }), racine $relative)." 'WARN'
    exit 2
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $powershell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }
$script = Join-Path $root 'app\OffPatch.ps1'
$arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Resume' -f $script
Write-ResumeLog "Support trouvé : $root ; relance de $script -Resume (session $($state.sessionId))."
if ($PSCmdlet.ShouldProcess($script, 'Relance de l''interface avec -Resume')) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $powershell
    $info.Arguments = $arguments
    $info.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($info)
}
$root
exit 0
