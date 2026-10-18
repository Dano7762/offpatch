<#
.SYNOPSIS
    Point d'entrée d'OffPatch, lancé par Lancer-OffPatch.cmd et, avec -Resume, par resume.ps1 après un redémarrage.

.DESCRIPTION
    Provisoire jusqu'à l'interface WPF (phase 6) : la session automatique tourne en console par OffPatch-Cli.ps1
    -Action Auto (plan affiché, une confirmation ; avec -Resume, reprise sans confirmation). La fenêtre reste
    ouverte à la fin pour lire le bilan.

.PARAMETER Resume
    Reprise de la session automatique en cours (state.json), sans confirmation.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch.ps1
#>
[CmdletBinding()]
param(
    [switch]$Resume
)
Set-StrictMode -Version Latest

& (Join-Path $PSScriptRoot 'OffPatch-Cli.ps1') -Action Auto -Resume:$Resume
[void](Read-Host 'Appuyer sur Entrée pour fermer')
