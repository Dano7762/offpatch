<#
.SYNOPSIS
    OffPatch sans interface : mêmes opérations que l'interface, pour la reprise après redémarrage, le débogage et
    les tests.

.DESCRIPTION
    Squelette (phase 1) : charge le module, ouvre le journal, charge et valide la configuration, puis lance l'action
    demandée. Les actions sont branchées au fil des phases ; une action pas encore disponible le dit et sort avec le
    code 2. OffPatch installe uniquement des mises à jour : aucun paramètre de clé de produit, de profil ou de
    retrait (cahier des charges 2, 3.3).
    Codes de sortie : 0 réussite, 1 erreur (configuration invalide, échec), 2 action pas encore disponible.

.PARAMETER Action
    DepotUpdate : mise à jour du dépôt (avec -ListOnly : interroge sans rien télécharger).
    Plan : détection et plan pour ce PC, en lecture seule.
    InstallStep : exécution d'une étape du plan (-StepId).
    Report : écriture du rapport d'intervention.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('DepotUpdate', 'Plan', 'InstallStep', 'Report')][string]$Action,
    [switch]$ListOnly,
    [string]$StepId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module -Name (Join-Path $PSScriptRoot 'module\OffPatch\OffPatch.psd1') -Force -ErrorAction Stop
    $kind = 'Session'
    if ($Action -eq 'DepotUpdate') { $kind = 'Depot' }
    $context = Initialize-OpSession -Kind $kind -Root (Split-Path -Parent $PSScriptRoot)
    Write-Host "Journal : $($context.Log.Path)"
} catch {
    Write-Host "OffPatch : $($_.Exception.Message)"
    exit 1
}

switch ($Action) {
    default {
        $detail = ''
        if ($Action -eq 'DepotUpdate' -and $ListOnly) { $detail = ' (-ListOnly)' }
        if ($Action -eq 'InstallStep' -and $StepId) { $detail = " (étape $StepId)" }
        Write-Host "OffPatch : action $Action$detail pas encore disponible."
        exit 2
    }
}
