<#
.SYNOPSIS
    Essai sur un runner GitHub : téléchargement d'une source Office par les fonctions du module (Save-OpOdt,
    Save-OpOfficeSource), deux passages.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés : il télécharge plusieurs gigaoctets. N'installe rien.
      1. ODT : Get-OpOdtPlan puis Save-OpOdt (extraction élevée, R-07) dans tools\odt de la copie du dépôt ;
      2. source demandée (config\office\sources.json) : XML de Get-OpOfficeDownloadXml, Save-OpOfficeSource ;
      3. second passage dans le même dossier : la source doit être déclarée à jour ;
      4. élément office-source du manifeste (contrôlé par Test-OpManifest), puis purge d'une ancienne version
         fictive posée à côté de la vraie, et revérification des SHA-256 de la version courante ;
      5. relevé : versions, durées, contenu de v64.hash, dossiers de Office\Data, journal du dépôt.

.EXAMPLE
    .\Invoke-OfficeDownloadTest.ps1 -SourceId perpetualvl2021 -OutputDirectory $env:RUNNER_TEMP\office-download-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$SourceId,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script télécharge plusieurs gigaoctets : il ne s''exécute que sur un runner GitHub hébergé.'
}
if (-not $PSCmdlet.ShouldProcess($SourceId, 'Téléchargement de la source Office')) { return }

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$module = Import-Module -Name (Join-Path $toolRoot 'app\module\OffPatch\OffPatch.psd1') -Force -PassThru
$lines = & $module {
    param($Root, $Id, $Out)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## Source Office $Id par le module ($env:PROCESSOR_ARCHITECTURE)")
    $lines.Add('')
    Start-OpLog -Kind Depot -Directory (Join-Path $Out 'logs') | Out-Null
    $configuration = Get-OpConfiguration -Root $Root
    $odt = Get-OpOdtPlan -Configuration $configuration -Root $Root
    if ($odt.Error) { throw $odt.Error }
    $saved = Save-OpOdt -Plan $odt -Configuration $configuration -Root $Root -Confirm:$false
    $lines.Add("- ODT : $($odt.FileName), setup.exe $($saved.Version) (élevé : $(Test-OpElevated))")
    $source = @(Get-OpOfficeDownloadXml -Configuration $configuration -Root $Root | Where-Object { $_.Id -eq $Id })
    if ($source.Count -ne 1) { throw "Source $Id absente de config\office\sources.json." }
    $source[0].Xml | Set-Content -Path (Join-Path $Out "download-$Id.xml") -Encoding UTF8
    foreach ($pass in 1, 2) {
        $r = Save-OpOfficeSource -Source $source[0] -SetupPath $odt.SetupPath -Root $Root -Confirm:$false
        $lines.Add(('- Passage {0} : version {1}, lue dans v64.cab : {2}, précédente : {3}, nouvelle : {4}, {5} s' -f $pass, $r.Version, $r.FromIndex, $r.PreviousVersion, $r.Updated, $r.DurationSeconds))
    }
    $data = Join-Path $source[0].SourcePath 'Office\Data'
    $lines.Add('')
    $lines.Add('Office\Data :')
    foreach ($e in @(Get-ChildItem -LiteralPath $data | Sort-Object Name)) {
        $size = [long]0
        if ($e.PSIsContainer) { foreach ($f in @(Get-ChildItem -LiteralPath $e.FullName -Recurse -File)) { $size += $f.Length } } else { $size = $e.Length }
        $lines.Add(('    {0} : {1} Mo' -f $e.Name, [math]::Round($size / 1MB, 1)))
    }
    # Manifeste et purge (7.2, 7.3) : élément office-source de la vraie source, puis une ancienne version fictive
    # (dossier et v64_<version>.cab) posée à côté, que la purge doit retirer sans toucher à la version courante.
    $depot = Get-OpPath -Name Depot -Root $Root
    $folder = @($configuration.OfficeSources.sources | Where-Object { $_.id -eq $Id })[0].folder
    $item = ConvertTo-OpOfficeManifestItem -Result $r -Folder $folder -Depot $depot
    $problems = @(Test-OpManifest -Manifest ([pscustomobject]@{ schemaVersion = 1; items = @($item) }))
    if ($problems.Count -gt 0) { throw "Élément office-source invalide : $($problems -join ' ')" }
    Save-OpManifest -Manifest ([pscustomobject]@{ schemaVersion = 1; toolVersion = $null; items = @($item) }) -Path (Get-OpPath -Name Manifest -Root $Root) -Confirm:$false
    $total = [long]0
    foreach ($f in $item.files) { $total += $f.size }
    $lines.Add('')
    $lines.Add(('- Manifeste : {0}, {1} fichier(s), {2} Mo, valide' -f $item.id, @($item.files).Count, [math]::Round($total / 1MB, 1)))
    $old = Join-Path $data '16.0.1.1'
    New-Item -ItemType Directory -Force -Path $old | Out-Null
    Set-Content -Path (Join-Path $old 'stream.x64.fr-fr.dat') -Value 'ancienne version fictive' -Encoding ASCII
    Set-Content -Path (Join-Path $data 'v64_16.0.1.1.cab') -Value 'ancien index fictif' -Encoding ASCII
    $purge = Invoke-OpDepotPurge -Root $Root -Confirm:$false
    if ((Test-Path -LiteralPath $old) -or (Test-Path -LiteralPath (Join-Path $data 'v64_16.0.1.1.cab'))) { throw 'Purge : l''ancienne version fictive est toujours là.' }
    $changed = @($item.files | Where-Object { (Get-FileHash -LiteralPath (Join-Path $depot $_.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $_.sha256 })
    if ($changed.Count -gt 0) { throw "Purge : $($changed.Count) fichier(s) de la version courante modifié(s) ou absent(s)." }
    $lines.Add(('- Purge : retiré {0} ({1}) ; SHA-256 de la version courante revérifiés après purge' -f (@($purge.RemovedItems) -join ', '), (@($purge.RemovedFiles) -join ', ')))

    $hashFolder = Join-Path $Out 'v64'
    New-Item -ItemType Directory -Force -Path $hashFolder | Out-Null
    & (Join-Path $env:SystemRoot 'System32\expand.exe') '-F:*' (Join-Path $data 'v64.cab') $hashFolder | Out-Null
    $lines.Add('')
    $lines.Add('v64.hash :')
    foreach ($l in @(Get-Content -LiteralPath (Join-Path $hashFolder 'v64.hash'))) { $lines.Add('    ' + $l) }
    $lines
} $toolRoot $SourceId $OutputDirectory

$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Output $summary
