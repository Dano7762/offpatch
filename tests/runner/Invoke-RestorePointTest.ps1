<#
.SYNOPSIS
    Essai sur un runner GitHub : point de restauration avant session (bilan de phase 0).

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Relève :
      1. l'état initial de la protection du système sur C: (Get-ComputerRestorePoint, points existants) ;
      2. Checkpoint-Computer avec la protection telle qu'elle est (cas « protection désactivée » si c'est le cas) ;
      3. si elle était désactivée : Enable-ComputerRestore sur C: (runner jetable seulement ; OffPatch ne le fera
         jamais), puis Checkpoint-Computer : durée, espace libre de C: avant et après, stockage des clichés
         (vssadmin list shadowstorage), vérification par Get-ComputerRestorePoint ;
      4. second Checkpoint-Computer dans la foulée : comportement de la limite de 24 heures (erreur, avertissement
         ou rien) et vérification par Get-ComputerRestorePoint.

.EXAMPLE
    .\Invoke-RestorePointTest.ps1 -OutputDirectory $env:RUNNER_TEMP\rp-out
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

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$lines = New-Object System.Collections.Generic.List[string]

function Get-FreeGiB {
    [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace / 1GB, 3)
}

function Get-RestorePointList {
    try {
        @(Get-ComputerRestorePoint -ErrorAction Stop | ForEach-Object {
                '{0} « {1} » {2}' -f $_.SequenceNumber, $_.Description, $_.CreationTime
            })
    } catch {
        @("Get-ComputerRestorePoint en échec : $($_.Exception.Message)")
    }
}

function Invoke-Checkpoint {
    param([string]$Label)
    $before = Get-FreeGiB
    $countBefore = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    $started = Get-Date
    $warnings = $null
    $errorText = 'aucune'
    try {
        Checkpoint-Computer -Description "OffPatch essai $Label" -RestorePointType MODIFY_SETTINGS -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        $errorText = ($_.Exception.Message -replace '\s+', ' ').Trim()
    }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $after = Get-FreeGiB
    $countAfter = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
    $warningText = 'aucun'
    if ($warnings) { $warningText = (@($warnings | ForEach-Object { "$_" }) -join ' / ') }
    $lines.Add("- $Label : $seconds s ; erreur : $errorText ; avertissement : $warningText ; points avant/après : $countBefore → $countAfter ; C: libre $before → $after Gio")
}

try {
    $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $lines.Add("## Point de restauration ($($v.ProductName), $($v.DisplayVersion), $($v.CurrentBuild).$($v.UBR), $env:PROCESSOR_ARCHITECTURE)")
    $lines.Add('')
    $lines.Add('- Points existants au départ : ' + ((Get-RestorePointList) -join ' ; '))
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $sr = Get-ItemProperty -Path $srKey -ErrorAction SilentlyContinue
    if ($sr) {
        $props = @($sr.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value)" })
        $lines.Add('- Registre SystemRestore : ' + ($props -join ', '))
    }
    $lines.Add('- vssadmin avant : ' + ((& vssadmin.exe list shadowstorage 2>&1 | Out-String) -replace '\s+', ' ').Trim())
    $lines.Add('')

    if ($PSCmdlet.ShouldProcess('C:', 'Checkpoint-Computer, protection telle quelle')) { Invoke-Checkpoint -Label 'protection-initiale' }

    if ($PSCmdlet.ShouldProcess('C:', 'Enable-ComputerRestore puis Checkpoint-Computer')) {
        Enable-ComputerRestore -Drive "$env:SystemDrive\"
        $lines.Add('- Protection du système activée sur C: (runner jetable)')
        Invoke-Checkpoint -Label 'apres-activation'
        $lines.Add('- Points après : ' + ((Get-RestorePointList) -join ' ; '))
        $lines.Add('- vssadmin après : ' + ((& vssadmin.exe list shadowstorage 2>&1 | Out-String) -replace '\s+', ' ').Trim())
        Invoke-Checkpoint -Label 'second-dans-les-24-h'
        $lines.Add('- Points à la fin : ' + ((Get-RestorePointList) -join ' ; '))
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
