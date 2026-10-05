<#
.SYNOPSIS
    Télécharge et vérifie des fichiers à lien direct (éléments épinglés), sans les installer.

.DESCRIPTION
    Script réservé aux runners GitHub. Pour chaque URL : refus si le domaine n'est pas autorisé, relevé des
    redirections, téléchargement, taille, SHA-1 comparé à l'empreinte du nom de fichier, SHA-256, signature
    Authenticode et racine comparée à integrity.trustedRootThumbprints (un refus fait échouer le script). Le rapport a le même format que celui de Save-CatalogEntryFile.ps1 (Write-DownloadSummary.ps1).
    Sert à valider les liens de l'enablement package (R-03), absent du catalogue.

.EXAMPLE
    .\Test-PinnedFile.ps1 -Url 'https://catalog.sf.dl.delivery.mp.microsoft.com/…/Windows11.0-KB5121794-x64_<sha1>.msu' -Destination D:\pinned -ReportPath D:\out\download.json
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingBrokenHashAlgorithms', '', Justification = 'SHA-1 imposé par le nom de fichier Microsoft : comparaison d''empreinte, pas un contrôle de sécurité.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Url,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ReportPath,
    [string[]]$AllowedHost = @('catalog.sf.dl.delivery.mp.microsoft.com', 'catalog.s.download.windowsupdate.com')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $toolRoot 'app\module\OffPatch\Private\Test-OpFileSignature.ps1')
$trustedRoots = @((Get-Content -Path (Join-Path $toolRoot 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).integrity.trustedRootThumbprints)

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$files = foreach ($u in $Url) {
    $uri = [uri]$u
    if ($uri.Scheme -ne 'https' -or $AllowedHost -notcontains $uri.Host) {
        throw "Domaine non autorisé : $($uri.Host)"
    }
    $name = $uri.Segments[-1]
    $hosts = New-Object System.Collections.Generic.List[string]
    $hosts.Add($uri.Host)
    foreach ($line in (& curl.exe --silent --head --location --max-redirs 10 $u)) {
        if ($line -match '^(?i)location:\s*(\S+)' -and $Matches[1] -match '^https?://') {
            $redirect = ([uri]$Matches[1]).Host
            if ($AllowedHost -notcontains $redirect) { throw "Redirection vers un domaine non autorisé : $redirect" }
            $hosts.Add($redirect)
        }
    }

    $file = Join-Path $Destination $name
    $started = Get-Date
    & curl.exe --fail --silent --show-error --location --retry 3 --output $file $u
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour $name" }
    $sha1 = (Get-FileHash -Path $file -Algorithm SHA1).Hash.ToLowerInvariant()
    $expected = [regex]::Match($name, '_([0-9a-fA-F]{40})\.\w+$').Groups[1].Value.ToLowerInvariant()
    $signature = Get-AuthenticodeSignature -FilePath $file
    $signer = $null
    if ($signature.SignerCertificate) { $signer = $signature.SignerCertificate.Subject }
    $check = Test-OpFileSignature -Path $file -TrustedRootThumbprint $trustedRoots
    $item = [pscustomobject]@{
        Name               = $name
        Kb                 = [regex]::Match($name, '(?i)-(kb\d+)-').Groups[1].Value.ToUpperInvariant()
        Role               = 'pinned'
        Path               = $file
        Size               = (Get-Item $file).Length
        Sha256             = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLowerInvariant()
        Sha1               = $sha1
        Sha1FromName       = $expected
        Sha1Matches        = ($expected -eq $sha1)
        AuthenticodeStatus = [string]$signature.Status
        AuthenticodeType   = [string]$signature.SignatureType
        Signer             = $signer
        RootSubject        = $check.RootSubject
        RootThumbprint     = $check.RootThumbprint
        RootTrusted        = $check.IsTrusted
        SignatureReason    = $check.Reason
        Hosts              = @($hosts | Select-Object -Unique)
        Url                = $u
        DownloadSeconds    = [math]::Round(((Get-Date) - $started).TotalSeconds)
    }
    Write-Host ("{0} : {1} octets, SHA-1 conforme : {2}, Authenticode : {3} ({4})" -f $name, $item.Size, $item.Sha1Matches, $item.AuthenticodeStatus, $item.Signer)
    $item
}

$report = [pscustomobject]@{
    Kb         = (@($files | ForEach-Object { $_.Kb } | Select-Object -Unique) -join ', ')
    Arch       = (@($files | ForEach-Object { [regex]::Match($_.Name, '(?i)-(x64|arm64)_').Groups[1].Value.ToLowerInvariant() }) -join ', ')
    EntryTitle = 'Liens directs (éléments épinglés)'
    EntryId    = $null
    Files      = @($files)
}
$reportFolder = Split-Path -Parent $ReportPath
if ($reportFolder) { New-Item -ItemType Directory -Force -Path $reportFolder | Out-Null }
$report | ConvertTo-Json -Depth 5 | Set-Content -Path ($ReportPath + '.tmp') -Encoding UTF8
Move-Item -Path ($ReportPath + '.tmp') -Destination $ReportPath -Force
# Critères du cahier des charges (7.1) : un fichier refusé fait échouer le job, après écriture du rapport.
$refused = @($report.Files | Where-Object { -not $_.RootTrusted })
if ($refused.Count -gt 0) {
    throw ("Signature refusée : " + (@($refused | ForEach-Object { "$($_.Name) : $($_.SignatureReason)" }) -join ' ; '))
}
