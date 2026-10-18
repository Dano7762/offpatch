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
      3. Support absent : une petite fenêtre demande de le rebrancher et la recherche reprend toutes les
         PollSeconds secondes, jusqu'à ce qu'il soit trouvé (sur n'importe quelle lettre) ou que l'attente soit
         abandonnée (bouton ou fermeture de la fenêtre). L'état de session est conservé dans tous les cas.
      4. Relance <racine>\app\OffPatch.ps1 -Resume avec le PowerShell natif du système (Sysnative depuis un
         processus 32 bits sur Windows 64 bits, comme Lancer-OffPatch.cmd), sans attendre sa fin.
    Journal : ProgramData\OffPatch\logs\resume_AAAA-MM-JJ_HHMMSS.log.
    Codes de sortie : 0 interface relancée, 1 état de session absent ou illisible, 2 support introuvable (attente
    abandonnée ou délai dépassé).

.PARAMETER StatePath
    Chemin de state.json ; par défaut ProgramData\OffPatch\state.json.

.PARAMETER PollSeconds
    Intervalle entre deux recherches du support pendant l'attente ; 5 secondes par défaut (8.6).

.PARAMETER TimeoutSeconds
    Durée maximale de l'attente du support ; 0 (par défaut) : sans limite.

.PARAMETER NoWindow
    Attend le support sans fenêtre, avec un message dans la console (débogage, tests).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\OffPatch\resume.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StatePath,
    [ValidateRange(1, 3600)][int]$PollSeconds = 5,
    [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
    [switch]$NoWindow
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

# Attente du support : recherche toutes les $Poll secondes ; $null si l'attente est abandonnée ou expire ($Timeout,
# 0 : sans limite). Petite fenêtre non modale, message et bouton Abandonner ; la fermer revient à abandonner.
function Wait-ResumeSupport([string]$Serial, [string]$RelativeRoot, [int]$Poll, [int]$Timeout, [bool]$Console) {
    $message = "Le support OffPatch est introuvable. Rebranchez-le (dossier $RelativeRoot) : la session reprendra dès qu'il sera détecté, vérification toutes les $Poll secondes."
    $form = $null
    if ($Console) {
        Write-Host $message
    } else {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'OffPatch : reprise de la session'
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        $form.ClientSize = New-Object System.Drawing.Size 420, 150
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $message
        $label.SetBounds(15, 15, 390, 85)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = 'Abandonner'
        $button.SetBounds(305, 110, 100, 28)
        $button.Add_Click({ $form.Close() }.GetNewClosure())
        $form.Controls.AddRange(@($label, $button))
        $form.Show()
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $next = $Poll
    try {
        while ($true) {
            if ($form) {
                [System.Windows.Forms.Application]::DoEvents()
                if ($form.IsDisposed -or -not $form.Visible) { Write-ResumeLog 'Attente du support abandonnée.' 'WARN'; return $null }
            }
            if ($clock.Elapsed.TotalSeconds -ge $next) {
                $found = Find-ResumeSupport $Serial $RelativeRoot
                if ($found) { Write-ResumeLog "Support rebranché après $([int]$clock.Elapsed.TotalSeconds) s."; return $found }
                $next += $Poll
            }
            if ($Timeout -gt 0 -and $clock.Elapsed.TotalSeconds -ge $Timeout) { Write-ResumeLog "Support toujours absent après $Timeout s." 'WARN'; return $null }
            Start-Sleep -Milliseconds 200
        }
    } finally {
        if ($form) { $form.Dispose() }
    }
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
    Write-ResumeLog "Support introuvable (volume $(if ($serial) { $serial } else { 'inconnu' }), racine $relative) : attente du rebranchement." 'WARN'
    $root = Wait-ResumeSupport $serial $relative $PollSeconds $TimeoutSeconds ([bool]$NoWindow)
    if (-not $root) {
        Write-ResumeLog 'Session conservée : elle pourra être reprise au prochain lancement d''OffPatch.' 'WARN'
        exit 2
    }
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
