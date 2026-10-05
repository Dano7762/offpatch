<#
.SYNOPSIS
    Enregistre des pages réelles du Microsoft Update Catalog comme fixtures des tests Pester.

.DESCRIPTION
    Lecture seule : cinq requêtes au catalogue, aucun téléchargement de fichier. À relancer quand le site
    change de structure, puis à committer avec la date de capture (fichier capture.txt).
      - search-kb5129195.html  : recherche par KB, 6 lignes ;
      - search-full.html       : recherche large, première page pleine (25 lignes) ;
      - search-full-last.html  : même recherche, dernière page (paramètre &p=, index à partir de 0) ;
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
    param([string]$Query, [string]$Name, [int]$PageIndex = 0)
    $uri = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($Query)
    if ($PageIndex -gt 0) { $uri += '&p=' + $PageIndex }
    $html = (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
    [System.IO.File]::WriteAllText((Join-Path $Destination $Name), $html, (New-Object System.Text.UTF8Encoding $false))
    $html
}

$kb = Save-SearchPage -Query 'KB5129195' -Name 'search-kb5129195.html'
$fullQuery = '2026-09 Cumulative Update Windows 11'
$full = Save-SearchPage -Query $fullQuery -Name 'search-full.html'
$pageCount = [int][regex]::Match($full, '\(page 1 of (\d+)\)').Groups[1].Value
if ($pageCount -lt 2) { throw "La recherche « $fullQuery » ne tient plus sur plusieurs pages : choisir une recherche plus large." }
Save-SearchPage -Query $fullQuery -Name 'search-full-last.html' -PageIndex ($pageCount - 1) | Out-Null
Save-SearchPage -Query 'KB0000000 OffPatch' -Name 'search-noresult.html' | Out-Null

$row = [regex]::Matches($kb, '(?s)<tr id="([0-9a-f\-]{36})_R\d+".*?</tr>') | Where-Object { $_.Value -match 'x64-based Systems' } | Select-Object -First 1
$id = $row.Groups[1].Value
$body = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $id + '","updateID":"' + $id + '"}]')
$dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing).Content
[System.IO.File]::WriteAllText((Join-Path $Destination 'dialog-kb5129195.html'), $dialog, (New-Object System.Text.UTF8Encoding $false))

Set-Content -Path (Join-Path $Destination 'capture.txt') -Value ("Capturé le {0:yyyy-MM-dd HH:mm} UTC, entrée de la fenêtre : {1}" -f (Get-Date).ToUniversalTime(), $id) -Encoding UTF8
