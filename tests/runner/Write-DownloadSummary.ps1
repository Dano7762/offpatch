<#
.SYNOPSIS
    Écrit le résumé d'un rapport de téléchargement produit par Save-CatalogEntryFile.ps1.

.DESCRIPTION
    Script réservé aux runners GitHub. Lit le rapport JSON, écrit un tableau Markdown (taille, dépassement
    de 4 Gio, SHA-1, Authenticode, domaines) dans le résumé du job GitHub et dans un fichier.
    Les données servent à R-10 (intégrité), R-12 (volumes) et R-13 (domaines).

.EXAMPLE
    .\Write-DownloadSummary.ps1 -ReportPath D:\out\download.json -OutputPath D:\out\resume.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReportPath,
    [Parameter(Mandatory)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$report = Get-Content -Path $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fat32Limit = [int64]4GB - 1
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Téléchargement : $($report.Kb) ($($report.Arch))")
$lines.Add('')
$lines.Add("Entrée : $($report.EntryTitle)")
$lines.Add('')
$lines.Add('| Fichier | Rôle | Octets | > 4 Gio | SHA-1 = nom | Authenticode | Type | Signataire | Racine (empreinte) | Racine de confiance | Domaines | Durée (s) |')
$lines.Add('|---|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($f in $report.Files) {
    $rootTrusted = $null
    $rootText = $null
    if ($f.PSObject.Properties['RootTrusted']) { $rootTrusted = $f.RootTrusted; $rootText = "$($f.RootSubject) ($($f.RootThumbprint))" }
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} |' -f $f.Name, $f.Role, $f.Size, ([int64]$f.Size -gt $fat32Limit), $f.Sha1Matches, $f.AuthenticodeStatus, $f.AuthenticodeType, $f.Signer, $rootText, $rootTrusted, (@($f.Hosts) -join ' → '), $f.DownloadSeconds))
}
$summary = $lines -join "`n"
$summary | Set-Content -Path $OutputPath -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
