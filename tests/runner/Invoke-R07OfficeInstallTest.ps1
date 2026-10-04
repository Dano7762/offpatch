<#
.SYNOPSIS
    Essai R-07 sur un runner GitHub : purge d'une source Office puis installation hors ligne.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
      1. récupère l'ODT par la page officielle du Centre de téléchargement ;
      2. télécharge une version ancienne puis la dernière version de la source (même dossier) ;
      3. applique la règle de purge déduite du premier essai : conserver la version désignée par v64.cab
         (v64.hash), supprimer les autres dossiers de version et leurs v64_<version>.cab ;
      4. bloque les domaines du CDN Office (fichier hosts) pour prouver l'installation hors ligne ;
      5. installe le produit avec AllowCdnFallback="FALSE", puis relève code retour, version installée,
         architecture des binaires et journaux de l'ODT ;
      6. rétablit le fichier hosts.

.EXAMPLE
    .\Invoke-R07OfficeInstallTest.ps1 -Channel Current -ProductId Home2024Retail -OlderVersion 16.0.20430.20092 -OutputDirectory $env:RUNNER_TEMP\r07i-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]+$')][string]$Channel,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]+$')][string]$ProductId,
    [ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Language = 'fr-fr',
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$OlderVersion,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DownloadPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117',
    [string[]]$BlockedHost = @('officecdn.microsoft.com', 'f.c2r.ts.cdn.office.net')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r07i-work'
$odtFolder = Join-Path $work 'odt'
$source = Join-Path $work 'source'
New-Item -ItemType Directory -Force -Path $odtFolder, $source | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-07 : installation hors ligne de $ProductId ($Channel, $Language) sur $env:PROCESSOR_ARCHITECTURE")
$lines.Add('')

function Get-SourceVersion {
    $data = Join-Path $source 'Office\Data'
    $folders = @(Get-ChildItem -Path $data -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { $_.Name })
    $cabs = @(Get-ChildItem -Path $data -File -Filter 'v64*.cab' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $size = [int64]0
    foreach ($f in @(Get-ChildItem -Path $source -Recurse -File)) { $size += $f.Length }
    $current = $null
    $cab = Join-Path $data 'v64.cab'
    if (Test-Path $cab) {
        $tmp = Join-Path $work 'v64-read'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        & expand.exe '-F:v64.hash' $cab $tmp | Out-Null
        $current = (Get-Content -Path (Join-Path $tmp 'v64.hash'))[1].Trim()
    }
    [pscustomobject]@{ Folders = $folders; Cabs = $cabs; Current = $current; SizeMB = [math]::Round($size / 1MB, 1) }
}

function Add-SourceLine {
    param([string]$Label)
    $state = Get-SourceVersion
    $lines.Add(('- Source après {0} : version désignée par v64.cab = {1} ; dossiers de version : {2} ; cab : {3} ; {4} Mo' -f $Label, $state.Current, ($state.Folders -join ', '), ($state.Cabs -join ', '), $state.SizeMB))
    $state
}

function Invoke-Odt {
    param([string]$Mode, [string]$Xml, [string]$Label)
    $config = Join-Path $OutputDirectory "$Label.xml"
    Set-Content -Path $config -Value $Xml -Encoding UTF8
    $started = Get-Date
    $process = Start-Process -FilePath (Join-Path $odtFolder 'setup.exe') -ArgumentList "/$Mode", $config -Wait -PassThru -WorkingDirectory $odtFolder
    $lines.Add(('- `setup.exe /{0}` ({1}) : code {2}, {3} s' -f $Mode, $Label, $process.ExitCode, [math]::Round(((Get-Date) - $started).TotalSeconds)))
    $process.ExitCode
}

function Get-PeMachine {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 'absent' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
    switch ($machine) { 0x8664 { 'x64' } 0xAA64 { 'ARM64' } 0xA641 { 'ARM64EC' } 0x014C { 'x86' } default { '0x{0:X4}' -f $machine } }
}

$hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$hostsBackup = Join-Path $work 'hosts.bak'
try {
    # 1. ODT
    $page = (Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing).Content
    $odtUrl = [regex]::Matches($page, 'https://download\.microsoft\.com/[^"\\ ]+officedeploymenttool[^"\\ ]+\.exe') | ForEach-Object { $_.Value } | Select-Object -First 1
    if (-not $odtUrl) { throw 'Lien officedeploymenttool_*.exe introuvable' }
    $odtExe = Join-Path $work ([uri]$odtUrl).Segments[-1]
    & curl.exe --fail --silent --show-error --location --retry 3 --output $odtExe $odtUrl
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour l'ODT" }
    Start-Process -FilePath $odtExe -ArgumentList '/quiet', "/extract:$odtFolder" -Wait | Out-Null
    $lines.Add("- ODT : $(([uri]$odtUrl).Segments[-1]), setup.exe $((Get-Item (Join-Path $odtFolder 'setup.exe')).VersionInfo.FileVersion)")

    # 2. Deux versions dans la même source
    $downloadTemplate = @'
<Configuration>
  <Add SourcePath="{0}" OfficeClientEdition="64" Channel="{1}"{2}>
    <Product ID="{3}">
      <Language ID="{4}" />
    </Product>
  </Add>
</Configuration>
'@
    if ($OlderVersion) {
        Invoke-Odt -Mode 'download' -Label 'download-ancienne' -Xml ($downloadTemplate -f $source, $Channel, " Version=""$OlderVersion""", $ProductId, $Language) | Out-Null
        Add-SourceLine -Label 'téléchargement de la version ancienne' | Out-Null
    }
    Invoke-Odt -Mode 'download' -Label 'download-derniere' -Xml ($downloadTemplate -f $source, $Channel, '', $ProductId, $Language) | Out-Null
    $before = Add-SourceLine -Label 'téléchargement de la dernière version'

    # 3. Purge : on garde la version désignée par v64.cab
    $data = Join-Path $source 'Office\Data'
    if ($before.Current -and $PSCmdlet.ShouldProcess($data, 'Purge des anciennes versions')) {
        foreach ($version in $before.Folders | Where-Object { $_ -ne $before.Current }) {
            Remove-Item -Path (Join-Path $data $version) -Recurse -Force
            $oldCab = Join-Path $data "v64_$version.cab"
            if (Test-Path $oldCab) { Remove-Item -Path $oldCab -Force }
        }
    }
    $after = Add-SourceLine -Label 'purge'
    $lines.Add(('- Contrôle de la purge : une seule version restante ({0}), égale à v64.cab : {1}' -f ($after.Folders.Count -eq 1), ($after.Folders -contains $after.Current)))

    # 4. Blocage du CDN pendant l'installation
    Copy-Item -Path $hostsFile -Destination $hostsBackup -Force
    Add-Content -Path $hostsFile -Value (($BlockedHost | ForEach-Object { "0.0.0.0 $_" }) -join "`r`n") -Encoding ASCII
    & ipconfig.exe /flushdns | Out-Null
    $lines.Add("- CDN bloqué pendant l'installation (hosts) : $($BlockedHost -join ', ')")

    # 5. Installation hors ligne
    $installXml = @"
<Configuration>
  <Add SourcePath="$source" OfficeClientEdition="64" Channel="$Channel" AllowCdnFallback="FALSE">
    <Product ID="$ProductId">
      <Language ID="$Language" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" Channel="$Channel" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
    if ($PSCmdlet.ShouldProcess($ProductId, 'Installation d''Office')) {
        Invoke-Odt -Mode 'configure' -Label 'install' -Xml $installXml | Out-Null
    }
    $c2r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($c2r) {
        $lines.Add(('- ClickToRun : VersionToReport {0}, Platform {1}, ProductReleaseIds {2}, UpdateChannel {3}, CDNBaseUrl {4}' -f $c2r.VersionToReport, $c2r.Platform, $c2r.ProductReleaseIds, $c2r.UpdateChannel, $c2r.CDNBaseUrl))
    } else {
        $lines.Add('- ClickToRun : clé de configuration absente (Office non installé)')
    }
    $root = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16'
    foreach ($exe in 'WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE') {
        $path = Join-Path $root $exe
        $version = $null
        if (Test-Path $path) { $version = (Get-Item $path).VersionInfo.FileVersion }
        $lines.Add(('- {0} : architecture {1}, version {2}' -f $exe, (Get-PeMachine -Path $path), $version))
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    if (Test-Path $hostsBackup) {
        Copy-Item -Path $hostsBackup -Destination $hostsFile -Force
        & ipconfig.exe /flushdns | Out-Null
    }
    foreach ($folder in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))) {
        Get-ChildItem -Path $folder -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-3) } |
            Copy-Item -Destination $OutputDirectory -ErrorAction SilentlyContinue
    }
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
