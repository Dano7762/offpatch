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
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('Enabled', 'Disabled', 'Indicators')][string]$Scenario = 'Enabled'
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

function Get-ProtectionProbe {
    # Trois indicateurs de l'état de la protection du système, aucun n'étant documenté comme référence.
    $wmi = 'indisponible'
    try {
        $cfg = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestoreConfig -ErrorAction Stop
        $wmi = (@($cfg.PSObject.Properties | Where-Object { $_.Name -notmatch '^(PS|Cim)' -and $null -ne $_.Value } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')
    } catch { $wmi = "erreur : $($_.Exception.Message)" }
    $spp = 'absente'
    $sppKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -ErrorAction SilentlyContinue
    if ($sppKey) { $spp = (@($sppKey.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$(@($_.Value) -join ';')" }) -join ', ') }
    $vss = ((& vssadmin.exe list shadowstorage 2>&1 | Out-String) -replace '\s+', ' ' -replace '^.*Corp\. ', '').Trim()
    "WMI SystemRestoreConfig : $wmi | SPP\Clients : $spp | vssadmin : $vss"
}

function Get-ProtectionIndicator {
    # Les deux indicateurs retenus pour le cahier des charges (8.2) :
    #  - SPP\Clients : une valeur dont les données citent le volume système (mesuré, non documenté) ;
    #  - Win32_ShadowStorage : une réservation de clichés pour le volume système (classe WMI documentée).
    $volume = Get-CimInstance Win32_Volume -Filter "DriveLetter='$env:SystemDrive'"
    $sppEntries = @()
    $sppKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -ErrorAction SilentlyContinue
    if ($sppKey) {
        $sppEntries = @($sppKey.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and (@($_.Value) -join ';') -like "*$($volume.DeviceID)*" })
    }
    $storage = @(Get-CimInstance Win32_ShadowStorage -ErrorAction SilentlyContinue | Where-Object { $_.Volume.DeviceID -eq $volume.DeviceID })
    $storageText = 'aucune'
    if ($storage.Count -gt 0) {
        $s = $storage[0]
        $storageText = 'allouée {0:N1} Mo, utilisée {1:N1} Mo, maximum {2:N1} Go' -f ($s.AllocatedSpace / 1MB), ($s.UsedSpace / 1MB), ($s.MaxSpace / 1GB)
    }
    [pscustomobject]@{
        Spp       = ($sppEntries.Count -gt 0)
        Storage   = ($storage.Count -gt 0)
        Text      = "SPP\Clients cite C: : $($sppEntries.Count -gt 0) ; Win32_ShadowStorage pour C: : $storageText"
    }
}

function Add-IndicatorLine {
    param([string]$Label)
    $i = Get-ProtectionIndicator
    $verdict = 'désaccord'
    if ($i.Spp -and $i.Storage) { $verdict = 'active' } elseif (-not $i.Spp -and -not $i.Storage) { $verdict = 'inactive' }
    $lines.Add("| $Label | $($i.Spp) | $($i.Storage) | $verdict | $($i.Text) |")
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

    if ($Scenario -eq 'Indicators') {
        # Les deux indicateurs dans chaque état : départ, protection activée, après un point, protection désactivée.
        $lines.Add('| Étape | SPP\Clients | Win32_ShadowStorage | Verdict (concordance) | Détail |')
        $lines.Add('|---|---|---|---|---|')
        Add-IndicatorLine -Label 'départ (image du runner)'
        if ($PSCmdlet.ShouldProcess('C:', 'Enable-ComputerRestore, point, Disable-ComputerRestore')) {
            Enable-ComputerRestore -Drive "$env:SystemDrive\"
            Add-IndicatorLine -Label 'après Enable-ComputerRestore'
            Checkpoint-Computer -Description 'OffPatch essai indicateurs' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
            Add-IndicatorLine -Label 'après Checkpoint-Computer (protection active)'
            Disable-ComputerRestore -Drive "$env:SystemDrive\"
            Add-IndicatorLine -Label 'après Disable-ComputerRestore'
            Start-Sleep -Seconds 30
            Add-IndicatorLine -Label 'après Disable-ComputerRestore, 30 s plus tard'
        }
        $lines.Add('')
        $lines.Add('- Points à la fin : ' + ((Get-RestorePointList) -join ' ; '))
        return
    }

    if ($Scenario -eq 'Disabled') {
        # Protection désactivée d'abord (runner jetable) : que fait Checkpoint-Computer, et que voit-on ?
        if ($PSCmdlet.ShouldProcess('C:', 'Disable-ComputerRestore puis Checkpoint-Computer')) {
            $lines.Add('- État au départ : ' + (Get-ProtectionProbe))
            Disable-ComputerRestore -Drive "$env:SystemDrive\"
            $lines.Add('- Protection du système désactivée sur C: (runner jetable)')
            $lines.Add('- État après désactivation : ' + (Get-ProtectionProbe))
            Invoke-Checkpoint -Label 'protection-desactivee'
            $lines.Add('- État après Checkpoint-Computer : ' + (Get-ProtectionProbe))
            $lines.Add('- Points après : ' + ((Get-RestorePointList) -join ' ; '))
        }
        return
    }

    $lines.Add('- État au départ : ' + (Get-ProtectionProbe))
    if ($PSCmdlet.ShouldProcess('C:', 'Checkpoint-Computer, protection telle quelle')) { Invoke-Checkpoint -Label 'protection-initiale' }
    $lines.Add('- État après le premier Checkpoint-Computer : ' + (Get-ProtectionProbe))

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
