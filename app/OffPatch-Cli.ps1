<#
.SYNOPSIS
    OffPatch sans interface : mêmes opérations que l'interface, pour la reprise après redémarrage, le débogage et
    les tests.

.DESCRIPTION
    Charge le module, ouvre le journal, charge et valide la configuration, puis lance l'action demandée :
      - DepotUpdate -ListOnly : liste de ce qui serait téléchargé, liens contrôlés, espace libre ; code 1 si un lien
        est refusé. DepotUpdate : téléchargement, contrôle, manifeste, résumé des nouveautés ; code 1 si un lien est
        refusé ou si un élément n'a pas pu être inscrit ;
      - Plan : relevé du PC, contrôles préalables et plan, en lecture seule ;
      - InstallStep -StepId <id> : une étape du plan (refusée si elle n'est pas « À installer » ou si un contrôle
        préalable est bloquant) ; code 1 si elle est refusée ou en erreur ; le redémarrage nécessaire est signalé,
        jamais lancé ;
      - Report : rapport d'intervention de la session (étapes exécutées et plan du moment), puis fin de session ;
      - Auto : session automatique (plan affiché, une confirmation, étapes, redémarrages avec reprise, rapport) ;
        -Resume : reprise après redémarrage, sans confirmation (relancée par resume.ps1 via OffPatch.ps1).
    OffPatch installe uniquement des mises à jour : aucun paramètre de clé de produit, de profil ou de retrait
    (cahier des charges 2, 3.3).
    Codes de sortie : 0 réussite, 1 erreur (configuration invalide, étape refusée ou en échec).

.PARAMETER Action
    DepotUpdate : mise à jour du dépôt (avec -ListOnly : interroge sans rien télécharger).
    Plan : détection et plan pour ce PC, en lecture seule.
    InstallStep : exécution d'une étape du plan (-StepId).
    Report : écriture du rapport d'intervention.
    Auto : session automatique ; avec -Resume, reprise sans confirmation.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action InstallStep -StepId <id>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('DepotUpdate', 'Plan', 'InstallStep', 'Report', 'Auto')][string]$Action,
    [switch]$ListOnly,
    [string]$StepId,
    [switch]$Resume
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module -Name (Join-Path $PSScriptRoot 'module\OffPatch\OffPatch.psd1') -Force -ErrorAction Stop
    $kind = 'Session'
    if ($Action -eq 'DepotUpdate') { $kind = 'Depot' }
    $context = Initialize-OpSession -Kind $kind -Root (Split-Path -Parent $PSScriptRoot) -Console
    Write-Host "Journal : $($context.Log.Path)"
} catch {
    Write-Host "OffPatch : $($_.Exception.Message)"
    exit 1
}

switch ($Action) {
    'DepotUpdate' {
        try {
            $result = Invoke-OpDepotUpdate -ListOnly:$ListOnly -Root $context.Root -WhatIf:$WhatIfPreference
            foreach ($line in Format-OpDepotPlan -Result $result) { Write-Host $line }
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if ($result.ErrorCount -gt 0) { exit 1 }
        exit 0
    }
    'Plan' {
        try {
            $info = Get-OpSystemInfo -Root $context.Root
            Write-Host "PC : $($info.ComputerName), $($info.Caption) $($info.DisplayVersion), build $($info.CurrentBuild).$($info.Ubr), cible $($info.Target)"
            Write-Host 'Contrôles préalables :'
            Write-Host (Test-OpPreflight -Root $context.Root -SystemInfo $info | Format-Table Label, Result, Message -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
            Write-Host 'Plan :'
            Write-Host (Get-OpInstallPlan -Root $context.Root -SystemInfo $info | Format-Table Sequence, Category, Id, State, RebootAfter, Reason -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        exit 0
    }
    'InstallStep' {
        if (-not $StepId) {
            Write-Host 'OffPatch : -StepId est obligatoire avec InstallStep (identifiant affiché par -Action Plan).'
            exit 1
        }
        try {
            $result = Invoke-OpInstallStep -StepId $StepId -Root $context.Root -WhatIf:$WhatIfPreference
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if (-not $result) { exit 0 }
        Write-Host "Étape $($result.Id) : $($result.State). $($result.Reason)"
        $reboot = $result.RebootAfter -or ($result.PSObject.Properties['RebootRequired'] -and $result.RebootRequired)
        if ($reboot) { Write-Host 'Redémarrage nécessaire avant l''étape suivante.' }
        if ($result.State -eq 'Error') { exit 1 }
        exit 0
    }
    'Report' {
        try {
            $path = Write-OpInstallReport -Root $context.Root -WhatIf:$WhatIfPreference
            if ($path) { Write-Host "Rapport : $path" }
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        exit 0
    }
    'Auto' {
        try {
            if (-not $Resume) {
                $info = Get-OpSystemInfo -Root $context.Root
                Write-Host 'Plan :'
                Write-Host (Get-OpInstallPlan -Root $context.Root -SystemInfo $info | Format-Table Sequence, Category, Id, State, RebootAfter, Reason -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
            }
            $onStep = { param($s) if ($s.PSObject.Properties['Seconds']) { Write-Host "Étape $($s.Id) : $($s.State). $($s.Reason)" } else { Write-Host "Étape $($s.Id) ($($s.Category)) : en cours…" } }
            $onTick = { param($left) Write-Host "Redémarrage dans $left s (Ctrl+C pour interrompre)" }
            $confirm = @{}
            if ($Resume) { $confirm.Confirm = $false }
            $result = Invoke-OpAutoSession -Root $context.Root -OnStep $onStep -OnTick $onTick -WhatIf:$WhatIfPreference @confirm
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if ($result) {
            Write-Host "Session automatique : $($result.Result)."
            if ($result.ReportPath) { Write-Host "Rapport : $($result.ReportPath)" }
        }
        exit 0
    }
}
