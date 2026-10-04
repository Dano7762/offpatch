<#
.SYNOPSIS
    Essai R-07 sur un runner GitHub : récupération de l'ODT et téléchargement d'une source Office.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés. Télécharge, n'installe rien.
      1. lit la page officielle du Centre de téléchargement (details.aspx?id=49117) et en extrait le lien
         officedeploymenttool_*.exe ; téléchargement, signature, extraction de setup.exe ;
      2. si -OlderVersion est donné : setup.exe /download de cette version dans le dossier source, relevé ;
      3. setup.exe /download de la dernière version dans le même dossier, relevé ;
      4. relevé de la structure (dossiers, nombre de fichiers, tailles), du contenu de v64.cab
         et des domaines cités dans les journaux de l'ODT (R-13).

.EXAMPLE
    .\Invoke-R07OfficeSourceTest.ps1 -Channel PerpetualVL2024 -ProductId ProPlus2024Volume -Language fr-fr -OlderVersion 16.0.17932.20976 -OutputDirectory $env:RUNNER_TEMP\r07-out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]+$')][string]$Channel,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]+$')][string]$ProductId,
    [ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Language = 'fr-fr',
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$OlderVersion,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DownloadPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script télécharge plusieurs gigaoctets : il ne s''exécute que sur un runner GitHub hébergé.'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r07-work'
$odtFolder = Join-Path $work 'odt'
$source = Join-Path $work 'source'
New-Item -ItemType Directory -Force -Path $odtFolder, $source | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-07 : source Office $ProductId, canal $Channel, $Language")
$lines.Add('')

# 1. ODT
$page = (Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing).Content
$odtUrl = [regex]::Matches($page, 'https://download\.microsoft\.com/[^"\\ ]+officedeploymenttool[^"\\ ]+\.exe') | ForEach-Object { $_.Value } | Select-Object -First 1
if (-not $odtUrl) { throw 'Lien officedeploymenttool_*.exe introuvable sur la page du Centre de téléchargement' }
$odtExe = Join-Path $work ([uri]$odtUrl).Segments[-1]
& curl.exe --fail --silent --show-error --location --retry 3 --output $odtExe $odtUrl
if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour l'ODT" }
$odtSignature = Get-AuthenticodeSignature -FilePath $odtExe
$extract = Start-Process -FilePath $odtExe -ArgumentList '/quiet', "/extract:$odtFolder" -Wait -PassThru
$setup = Join-Path $odtFolder 'setup.exe'
$lines.Add(('- ODT : {0} ({1} octets), Authenticode {2} ({3}), extraction `/quiet /extract:` code {4}, setup.exe présent : {5}, version {6}' -f ([uri]$odtUrl).Segments[-1], (Get-Item $odtExe).Length, $odtSignature.Status, $odtSignature.SignerCertificate.Subject, $extract.ExitCode, (Test-Path $setup), (Get-Item $setup).VersionInfo.FileVersion))

function Invoke-OfficeDownload {
    param([string]$Version, [string]$Label)
    $versionAttribute = ''
    if ($Version) { $versionAttribute = " Version=""$Version""" }
    $xml = @"
<Configuration>
  <Add SourcePath="$source" OfficeClientEdition="64" Channel="$Channel"$versionAttribute>
    <Product ID="$ProductId">
      <Language ID="$Language" />
    </Product>
  </Add>
</Configuration>
"@
    $config = Join-Path $OutputDirectory "download-$Label.xml"
    Set-Content -Path $config -Value $xml -Encoding UTF8
    $started = Get-Date
    $process = Start-Process -FilePath $setup -ArgumentList '/download', $config -Wait -PassThru -WorkingDirectory $odtFolder
    $lines.Add(('- `setup.exe /download` ({0}) : code {1}, {2} s' -f $Label, $process.ExitCode, [math]::Round(((Get-Date) - $started).TotalSeconds)))
    Add-SourceSnapshot -Label $Label
}

function Add-SourceSnapshot {
    param([string]$Label)
    $lines.Add('')
    $lines.Add("Structure après $Label :")
    $lines.Add('')
    foreach ($dir in @(Get-ChildItem -Path $source -Recurse -Directory | Sort-Object FullName)) {
        $files = @(Get-ChildItem -Path $dir.FullName -File)
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $lines.Add(('    {0} : {1} fichier(s), {2} Mo' -f $dir.FullName.Substring($source.Length), $files.Count, [math]::Round($size / 1MB, 1)))
    }
    $total = (Get-ChildItem -Path $source -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $lines.Add(('    Total : {0} Mo' -f [math]::Round($total / 1MB, 1)))
    foreach ($cab in @(Get-ChildItem -Path $source -Recurse -File -Filter 'v*.cab' | Where-Object { $_.DirectoryName -match '\\Data$' })) {
        $cabOut = Join-Path $OutputDirectory ("{0}-{1}" -f $Label, $cab.BaseName)
        New-Item -ItemType Directory -Force -Path $cabOut | Out-Null
        & expand.exe '-F:*' $cab.FullName $cabOut | Out-Null
        foreach ($f in Get-ChildItem -Path $cabOut -File) {
            $lines.Add(('    {0} contient {1} :' -f $cab.Name, $f.Name))
            foreach ($l in (Get-Content -Path $f.FullName -TotalCount 15)) { $lines.Add('        ' + $l) }
        }
    }
}

if ($OlderVersion) { Invoke-OfficeDownload -Version $OlderVersion -Label 'version-ancienne' }
Invoke-OfficeDownload -Version '' -Label 'derniere-version'

# Domaines cités dans les journaux de l'ODT (dossier temporaire de l'utilisateur)
$logs = @(Get-ChildItem -Path $env:TEMP -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-3) })
$hosts = @(foreach ($log in $logs) { [regex]::Matches((Get-Content -Path $log.FullName -Raw), 'https?://([a-z0-9.\-]+)') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } }) | Sort-Object -Unique
$lines.Add('')
$lines.Add("Domaines cités dans les journaux de l'ODT : $($hosts -join ', ')")
$logs | Copy-Item -Destination $OutputDirectory -ErrorAction SilentlyContinue

$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
