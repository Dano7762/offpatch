<#
.SYNOPSIS
    Enregistre des pages réelles du Microsoft Update Catalog comme fixtures des tests Pester.

.DESCRIPTION
    Lecture seule : quatre requêtes au catalogue, aucun téléchargement de fichier. À relancer quand le site
    change de structure, puis à committer avec la date de capture (fichier capture.txt).
      - search-kb5129195.html  : recherche par KB, 6 lignes ;
      - search-full.html       : recherche large, page pleine (25 lignes) ;
      - search-noresult.html   : recherche sans résultat ;
      - dialog-kb5129195.html  : fenêtre de téléchargement de la première entrée x64 de KB5129195.

.EXAMPLE
    .\tests\Fixtures\catalog\Save-CatalogFixture.ps1
#>
[CmdletBinding()]
param(
    [string]$Destination
)
if (-not $Destination) { $Destination = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Save-SearchPage {
    param([string]$Query, [string]$Name)
    $html = (Invoke-WebRequest -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($Query)) -UseBasicParsing).Content
    [System.IO.File]::WriteAllText((Join-Path $Destination $Name), $html, (New-Object System.Text.UTF8Encoding $false))
    $html
}

$kb = Save-SearchPage -Query 'KB5129195' -Name 'search-kb5129195.html'
Save-SearchPage -Query '2026-09 Cumulative Update Windows 11' -Name 'search-full.html' | Out-Null
Save-SearchPage -Query 'KB0000000 OffPatch' -Name 'search-noresult.html' | Out-Null

$row = [regex]::Matches($kb, '(?s)<tr id="([0-9a-f\-]{36})_R\d+".*?</tr>') | Where-Object { $_.Value -match 'x64-based Systems' } | Select-Object -First 1
$id = $row.Groups[1].Value
$body = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $id + '","updateID":"' + $id + '"}]')
$dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing).Content
[System.IO.File]::WriteAllText((Join-Path $Destination 'dialog-kb5129195.html'), $dialog, (New-Object System.Text.UTF8Encoding $false))

Set-Content -Path (Join-Path $Destination 'capture.txt') -Value ("Capturé le {0:yyyy-MM-dd HH:mm} UTC, entrée de la fenêtre : {1}" -f (Get-Date).ToUniversalTime(), $id) -Encoding UTF8
