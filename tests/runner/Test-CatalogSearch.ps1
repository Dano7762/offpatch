<#
.SYNOPSIS
    Répète une recherche au Microsoft Update Catalog et relève chaque essai (lecture seule).

.DESCRIPTION
    Script réservé aux runners GitHub. Sert au passage croisé qui sépare une cause réseau d'une cause de filtre
    après l'échec de recherche sur le runner ARM64 (R-01, R-02) : chaque essai appelle
    Save-CatalogEntryFile.ps1 -ListOnly ; un échec enregistre la page reçue dans le dossier de sortie.
    Aucun téléchargement de fichier.

.EXAMPLE
    .\Test-CatalogSearch.ps1 -Kb KB5129195 -Arch arm64 -Attempts 5 -OutputDirectory D:\out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^KB\d+$')][string]$Kb,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
    [ValidateRange(1, 20)][int]$Attempts = 5,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$results = foreach ($i in 1..$Attempts) {
    $diagnostic = Join-Path $OutputDirectory ("essai-{0}" -f $i)
    $started = Get-Date
    try {
        $urls = @(& (Join-Path $PSScriptRoot 'Save-CatalogEntryFile.ps1') -Kb $Kb -Arch $Arch -Destination $diagnostic -DiagnosticDirectory $diagnostic -ListOnly)
        [pscustomobject]@{ Attempt = $i; Success = $true; Links = $urls.Count; Error = $null; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds) }
    } catch {
        [pscustomobject]@{ Attempt = $i; Success = $false; Links = 0; Error = $_.Exception.Message; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds) }
    }
    Start-Sleep -Seconds 5
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Recherche au catalogue : $Kb ($Arch) depuis $env:PROCESSOR_ARCHITECTURE")
$lines.Add('')
$lines.Add('| Essai | Réussi | Liens | Durée (s) | Erreur |')
$lines.Add('|---|---|---|---|---|')
foreach ($r in $results) { $lines.Add("| $($r.Attempt) | $($r.Success) | $($r.Links) | $($r.Seconds) | $($r.Error) |") }
$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
