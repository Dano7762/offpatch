<#
.SYNOPSIS
    Télécharge les fichiers d'une entrée Windows 11 du Microsoft Update Catalog et relève leurs caractéristiques.

.DESCRIPTION
    Script réservé aux runners GitHub (jamais livré avec l'outil). Cherche l'entrée Windows 11 du KB demandé
    pour l'architecture voulue, résout ses liens (cumulative et checkpoints), télécharge chaque fichier avec
    curl.exe, puis relève pour chacun : taille, SHA-1 comparé à celui du nom de fichier, SHA-256, signature
    Authenticode, racine de la chaîne comparée à integrity.trustedRootThumbprints (config/settings.json) et
    domaines traversés par les redirections (R-10, R-12, R-13). Un fichier dont la signature est refusée
    fait échouer le script après l'écriture du rapport.
    La recherche et la lecture des pages passent par les fonctions du module (Find-OpCatalogUpdate, pagination).
    -AllowPreview accepte une préversion cumulative : réservé aux mesures (R-12), jamais retenu par OffPatch.
    Chaque fichier est rangé seul dans un dossier nommé par son SHA-256, comme dans le dépôt (cahier des charges, section 5).
    Aucune installation.

.EXAMPLE
    .\Save-CatalogEntryFile.ps1 -Kb KB5129195 -Arch arm64 -Destination D:\r02 -ReportPath D:\r02-out\download.json

.EXAMPLE
    .\Save-CatalogEntryFile.ps1 -Kb KB5129195 -Arch x64 -Destination D:\r02 -ListOnly
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingBrokenHashAlgorithms', '', Justification = 'SHA-1 imposé par le catalogue : comparaison avec l''empreinte du nom de fichier, pas un contrôle de sécurité.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^KB\d+$')][string]$Kb,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
    [Parameter(Mandatory)][string]$Destination,
    [string]$ReportPath,
    [string]$DiagnosticDirectory,
    [switch]$ListOnly,
    [switch]$AllowPreview
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$module = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'app\module\OffPatch\Private'
foreach ($name in 'ConvertFrom-OpCatalogSearchPage', 'ConvertFrom-OpCatalogDownloadDialog', 'Invoke-OpWebRequest', 'Find-OpCatalogUpdate', 'Test-OpFileSignature') {
    . (Join-Path $module "$name.ps1")
}
$settingsPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config\settings.json'
$trustedRoots = @((Get-Content -Path $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).integrity.trustedRootThumbprints)

function Get-CatalogEntryId {
    param([string]$Kb, [string]$Arch, [string]$DiagnosticDirectory, [switch]$AllowPreview)
    $exclude = 'Preview|Dynamic|Server|\.NET'
    if ($AllowPreview) { $exclude = 'Dynamic|Server|\.NET' }
    $titles = @()
    $lastError = $null
    foreach ($attempt in 1..3) {
        try {
            $items = @(Find-OpCatalogUpdate -Query $Kb)
            $titles = @($items | ForEach-Object { $_.Title })
            $entry = $items | Where-Object { $_.Title -match "Windows 11, version \d\dH\d for $Arch-based Systems" -and $_.Title -notmatch $exclude } | Select-Object -First 1
            if ($entry) { return [pscustomobject]@{ Id = $entry.UpdateId; Title = $entry.Title } }
            Write-Host ("Tentative {0} : {1} ligne(s) de résultat, aucune ne convient" -f $attempt, $items.Count)
        } catch {
            $lastError = $_.Exception.Message
            Write-Host ("Tentative {0} : {1}" -f $attempt, $lastError)
        }
        $titles | ForEach-Object { Write-Host "  $_" }
        Start-Sleep -Seconds (10 * $attempt)
    }
    if ($DiagnosticDirectory) {
        New-Item -ItemType Directory -Force -Path $DiagnosticDirectory | Out-Null
        try {
            $html = (Invoke-WebRequest -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + $Kb) -UseBasicParsing -ErrorAction Stop).Content
            Set-Content -Path (Join-Path $DiagnosticDirectory "catalog-search-$Kb.html") -Value $html -Encoding UTF8
        } catch {
            Write-Host "Page de diagnostic non récupérée : $($_.Exception.Message)"
        }
    }
    throw "Aucune entrée Windows 11 $Arch pour $Kb ($lastError)"
}

function Get-CatalogDownloadUrl {
    param([string]$EntryId)
    $payload = '[{"size":0,"languages":"","uidInfo":"' + $EntryId + '","updateID":"' + $EntryId + '"}]'
    $body = 'updateIDs=' + [uri]::EscapeDataString($payload)
    $dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop).Content
    @(ConvertFrom-OpCatalogDownloadDialog -Html $dialog | ForEach-Object { $_.Url })
}

function Get-RedirectHost {
    param([string]$Url)
    # Requête HEAD en suivant les redirections : on garde chaque hôte traversé.
    $hosts = New-Object System.Collections.Generic.List[string]
    $hosts.Add(([uri]$Url).Host)
    $headers = & curl.exe --silent --head --location --max-redirs 10 $Url
    foreach ($line in $headers) {
        if ($line -match '^(?i)location:\s*(\S+)') {
            $target = $Matches[1]
            if ($target -match '^https?://') { $hosts.Add(([uri]$target).Host) }
        }
    }
    @($hosts | Select-Object -Unique)
}

$entry = Get-CatalogEntryId -Kb $Kb -Arch $Arch -DiagnosticDirectory $DiagnosticDirectory -AllowPreview:$AllowPreview
Write-Host "Entrée : $($entry.Title)"
$urls = Get-CatalogDownloadUrl -EntryId $entry.Id
if ($ListOnly) {
    $urls
    return
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$files = foreach ($url in $urls) {
    $name = $url.Substring($url.LastIndexOf('/') + 1)
    $staging = Join-Path $Destination ($name + '.part')
    Write-Host "Téléchargement : $name"
    $hosts = Get-RedirectHost -Url $url
    $started = Get-Date
    & curl.exe --fail --silent --show-error --location --retry 3 --continue-at - --output $staging $url
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour $name" }
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds)

    $sha256 = (Get-FileHash -Path $staging -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha1 = (Get-FileHash -Path $staging -Algorithm SHA1).Hash.ToLowerInvariant()
    $folder = Join-Path $Destination $sha256
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $final = Join-Path $folder $name
    Move-Item -Path $staging -Destination $final -Force

    # Le nom de fichier du catalogue se termine par le SHA-1 du fichier (piste R-10).
    $expectedSha1 = [regex]::Match($name, '_([0-9a-f]{40})\.\w+$').Groups[1].Value
    $signature = Get-AuthenticodeSignature -FilePath $final
    $signer = $null
    if ($signature.SignerCertificate) { $signer = $signature.SignerCertificate.Subject }
    $check = Test-OpFileSignature -Path $final -TrustedRootThumbprint $trustedRoots
    $kbInName = [regex]::Match($name, '(?i)-(kb\d+)-').Groups[1].Value.ToUpperInvariant()

    $item = [pscustomobject]@{
        Name              = $name
        Kb                = $kbInName
        Role              = $(if ($kbInName -eq $Kb.ToUpperInvariant()) { 'target' } else { 'prerequisite' })
        Path              = $final
        Size              = (Get-Item $final).Length
        Sha256            = $sha256
        Sha1              = $sha1
        Sha1FromName      = $expectedSha1
        Sha1Matches       = ($expectedSha1 -eq $sha1)
        AuthenticodeStatus = [string]$signature.Status
        AuthenticodeType  = [string]$signature.SignatureType
        Signer            = $signer
        RootSubject       = $check.RootSubject
        RootThumbprint    = $check.RootThumbprint
        RootTrusted       = $check.IsTrusted
        SignatureReason   = $check.Reason
        Hosts             = $hosts
        Url               = $url
        DownloadSeconds   = $seconds
    }
    Write-Host ("  {0} octets, SHA-1 conforme : {1}, Authenticode : {2} ({3})" -f $item.Size, $item.Sha1Matches, $item.AuthenticodeStatus, $item.Signer)
    Write-Host ("  Racine : {0} ({1}), de confiance : {2} {3}" -f $item.RootSubject, $item.RootThumbprint, $item.RootTrusted, $item.SignatureReason)
    Write-Host ("  Domaines : {0}" -f ($hosts -join ', '))
    $item
}

$report = [pscustomobject]@{
    Kb         = $Kb
    Arch       = $Arch
    EntryTitle = $entry.Title
    EntryId    = $entry.Id
    Files      = @($files)
}
if ($ReportPath) {
    $reportFolder = Split-Path -Parent $ReportPath
    if ($reportFolder) { New-Item -ItemType Directory -Force -Path $reportFolder | Out-Null }
    $temp = $ReportPath + '.tmp'
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $temp -Encoding UTF8
    Move-Item -Path $temp -Destination $ReportPath -Force
}
# Critères du cahier des charges (7.1) : un fichier refusé fait échouer le job, après écriture du rapport.
$refused = @($report.Files | Where-Object { -not $_.RootTrusted })
if ($refused.Count -gt 0) {
    throw ("Signature refusée : " + (@($refused | ForEach-Object { "$($_.Name) : $($_.SignatureReason)" }) -join ' ; '))
}
$report
