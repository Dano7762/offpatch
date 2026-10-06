<#
.SYNOPSIS
    Essai R-02 sur un runner GitHub : installation séquentielle d'une cumulative et de ses checkpoints par DISM.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Étapes :
      1. contrôle des droits administrateur et de l'espace libre ;
      2. relevé initial : build, UBR, édition, Get-HotFix, liste des paquets DISM ;
      3. téléchargement de l'entrée du catalogue (Save-CatalogEntryFile.ps1), un fichier par dossier nommé par son SHA-256 ;
      4. méthode 1 de R-02 : DISM /Add-Package /NoRestart sur chaque prérequis (par numéro de KB croissant) puis sur la cible ;
      5. même chose une seconde fois, pour relever les codes retour quand les paquets sont déjà installés ;
      6. relevé final.
    Espace disque (R-12) : l'espace libre de C: est échantillonné toutes les 2 secondes pendant DISM ; le résumé donne
    la consommation finale (sans redémarrage) et le pic, avec la taille du magasin de composants avant et après
    (DISM /Cleanup-Image /AnalyzeComponentStore). -AllowPreview accepte une préversion cumulative, seule
    installable quand l'image du runner est déjà à jour : réservé à cette mesure.
    -PinnedItemId (élément de config/pinned-items.json, par exemple l'enablement package) : le fichier épinglé est
    téléchargé et contrôlé par Test-PinnedFile.ps1, puis passé à DISM au premier passage juste avant les prérequis
    de la cumulative, juste après la cible, ou les deux (-PinnedPosition), sans redémarrage (R-03, R-14).
    Les codes retour de DISM sont relevés, pas jugés : le script n'échoue que sur une erreur imprévue.

.EXAMPLE
    .\Invoke-R02CheckpointTest.ps1 -Kb KB5129195 -Arch arm64 -OutputDirectory $env:RUNNER_TEMP\r02-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^KB\d+$')][string]$Kb,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'arm64',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$WorkDirectory,
    [switch]$AllowPreview,
    [string]$PinnedItemId,
    [ValidateSet('Both', 'Before', 'After')][string]$PinnedPosition = 'Both'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}

$cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'

function Get-OsState {
    $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        ProductName    = $v.ProductName
        EditionId      = $v.EditionID
        InstallationType = $v.InstallationType
        DisplayVersion = $v.DisplayVersion
        CurrentBuild   = [int]$v.CurrentBuild
        Ubr            = [int]$v.UBR
        Architecture   = $env:PROCESSOR_ARCHITECTURE
        RebootPending  = (Test-Path $cbsKey)
    }
}

function Save-PackageInventory {
    param([string]$Suffix)
    & dism.exe /English /Online /Get-Packages /Format:Table | Out-File -FilePath (Join-Path $OutputDirectory "packages-$Suffix.txt") -Encoding UTF8
    Get-HotFix | Sort-Object HotFixID | Format-Table -AutoSize | Out-String -Width 200 | Out-File -FilePath (Join-Path $OutputDirectory "hotfix-$Suffix.txt") -Encoding UTF8
}

function Invoke-DismAddPackage {
    param([string]$Label, [string]$PackagePath)
    $log = Join-Path $OutputDirectory "dism-$Label.log"
    $console = Join-Path $OutputDirectory "dism-$Label-console.txt"
    $started = Get-Date
    $output = @(& dism.exe /English /Online /Add-Package "/PackagePath:$PackagePath" /NoRestart "/LogPath:$log")
    $code = $LASTEXITCODE
    $output | Out-File -FilePath $console -Encoding UTF8
    # Message de DISM : lignes utiles de la console, sans l'en-tête ni la barre de progression.
    $message = @($output | ForEach-Object { "$_".Trim() } | Where-Object {
            $_ -and $_ -notmatch '^\[[= ]*[\d.]*%?[= ]*\]$' -and $_ -notmatch '^(Deployment Image Servicing|Version:|Image Version:|HOTPATCHUTIL )'
        }) -join ' / '
    $result = [pscustomobject]@{
        Label         = $Label
        Package       = Split-Path -Leaf $PackagePath
        ExitCode      = $code
        ExitCodeHex   = ('0x{0:X8}' -f $code)
        Seconds       = [math]::Round(((Get-Date) - $started).TotalSeconds)
        RebootPending = (Test-Path $cbsKey)
        Ubr           = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
        Message       = $message
    }
    Write-Host ("{0} : code {1} ({2}), {3} s, redémarrage en attente : {4}" -f $Label, $result.ExitCode, $result.ExitCodeHex, $result.Seconds, $result.RebootPending)
    $result
}

function Get-SystemDriveFreeByte {
    [int64](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
}

function Get-ComponentStoreSize {
    # Analyse bornée à 10 minutes : avec un redémarrage en attente, elle n'a pas rendu la main en 4 h 30 (2026-10-05).
    param([string]$Suffix)
    $file = Join-Path $OutputDirectory "componentstore-$Suffix.txt"
    $process = Start-Process -FilePath 'dism.exe' -ArgumentList '/English', '/Online', '/Cleanup-Image', '/AnalyzeComponentStore' -RedirectStandardOutput $file -NoNewWindow -PassThru
    if (-not $process.WaitForExit(600000)) {
        $process.Kill()
        return 'non relevé (analyse arrêtée après 10 min)'
    }
    $line = @(Get-Content -Path $file | Where-Object { $_ -match 'Actual Size of Component Store\s*:\s*(.+)$' }) | Select-Object -First 1
    if ($line -and $line -match ':\s*(.+)$') { $Matches[1].Trim() } else { 'non relevé' }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

# 1. Droits et espace libre
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        [pscustomobject]@{ Drive = $_.DeviceID; FreeGB = [math]::Round($_.FreeSpace / 1GB, 1); SizeGB = [math]::Round($_.Size / 1GB, 1) }
    })
$drives | Format-Table -AutoSize | Out-String | Write-Host
if (-not $isAdmin) { throw 'Le runner ne donne pas les droits administrateur : essai impossible.' }
if (-not $WorkDirectory) {
    # Le téléchargement va sur le disque qui a le plus d'espace libre.
    $best = $drives | Sort-Object FreeGB -Descending | Select-Object -First 1
    $WorkDirectory = Join-Path ($best.Drive + '\') 'r02-work'
}
Write-Host "Dossier de travail : $WorkDirectory"

# 2. Relevé initial
$before = Get-OsState
$before | Format-List | Out-String | Write-Host
Save-PackageInventory -Suffix 'avant'

# 3. Téléchargement
$freeBeforeDownload = Get-SystemDriveFreeByte
$download = & (Join-Path $PSScriptRoot 'Save-CatalogEntryFile.ps1') -Kb $Kb -Arch $Arch -Destination $WorkDirectory -ReportPath (Join-Path $OutputDirectory 'download.json') -DiagnosticDirectory $OutputDirectory -AllowPreview:$AllowPreview
$prerequisites = @($download.Files | Where-Object { $_.Role -eq 'prerequisite' } | Sort-Object { [int]($_.Kb -replace '\D', '') })
$target = @($download.Files | Where-Object { $_.Role -eq 'target' })
if ($target.Count -ne 1) { throw "Cible introuvable ou en double pour $Kb dans l'entrée du catalogue." }
$freeAfterDownload = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { '{0} {1} Go' -f $_.DeviceID, [math]::Round($_.FreeSpace / 1GB, 1) })
Write-Host ("Espace libre après téléchargement : {0}" -f ($freeAfterDownload -join ', '))

# Élément épinglé (facultatif) : lien, SHA-1 et signature contrôlés par Test-PinnedFile.ps1.
$pinned = $null
if ($PinnedItemId) {
    $pinnedConfig = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config\pinned-items.json'
    $item = @((Get-Content -Path $pinnedConfig -Raw -Encoding UTF8 | ConvertFrom-Json).items | Where-Object { $_.id -eq $PinnedItemId })
    if ($item.Count -ne 1) { throw "Élément épinglé introuvable dans pinned-items.json : $PinnedItemId" }
    $pinnedReport = Join-Path $OutputDirectory 'pinned.json'
    & (Join-Path $PSScriptRoot 'Test-PinnedFile.ps1') -Url $item[0].url -Destination (Join-Path $WorkDirectory 'pinned') -ReportPath $pinnedReport
    $pinned = @((Get-Content -Path $pinnedReport -Raw -Encoding UTF8 | ConvertFrom-Json).Files)[0]
    if ($pinned.Sha1 -ne $item[0].sha1) { throw "SHA-1 de l'élément épinglé différent de pinned-items.json : $($pinned.Sha1)" }
}

# Espace disque pendant DISM : échantillonnage dans un job séparé, arrêté par un fichier témoin.
$storeBefore = Get-ComponentStoreSize -Suffix 'avant'
$freeBeforeDism = Get-SystemDriveFreeByte
$samplesPath = Join-Path $OutputDirectory 'espace-libre.csv'
$stopFlag = Join-Path $OutputDirectory 'arret-echantillonnage.flag'
$systemDrive = $env:SystemDrive
$sampler = Start-Job -ScriptBlock {
    $filter = "DeviceID='" + $using:systemDrive + "'"
    'Horodatage,OctetsLibres' | Set-Content -Path $using:samplesPath -Encoding UTF8
    while (-not (Test-Path $using:stopFlag)) {
        $free = (Get-CimInstance Win32_LogicalDisk -Filter $filter).FreeSpace
        ('{0:yyyy-MM-ddTHH:mm:ss},{1}' -f (Get-Date), $free) | Add-Content -Path $using:samplesPath -Encoding UTF8
        Start-Sleep -Seconds 2
    }
}

# 4 et 5. Méthode 1, puis répétition pour le cas « déjà installé »
$steps = New-Object System.Collections.Generic.List[object]
foreach ($pass in 1, 2) {
    if ($pinned -and $pass -eq 1 -and $PinnedPosition -ne 'After' -and $PSCmdlet.ShouldProcess($pinned.Name, 'DISM /Add-Package')) {
        $steps.Add((Invoke-DismAddPackage -Label ("passe1-epingle-avant-{0}" -f $pinned.Kb) -PackagePath $pinned.Path))
    }
    foreach ($p in $prerequisites) {
        if ($PSCmdlet.ShouldProcess($p.Name, 'DISM /Add-Package')) {
            $steps.Add((Invoke-DismAddPackage -Label ("passe{0}-prerequis-{1}" -f $pass, $p.Kb) -PackagePath $p.Path))
        }
    }
    if ($PSCmdlet.ShouldProcess($target[0].Name, 'DISM /Add-Package')) {
        $steps.Add((Invoke-DismAddPackage -Label ("passe{0}-cible-{1}" -f $pass, $target[0].Kb) -PackagePath $target[0].Path))
    }
    if ($pinned -and $pass -eq 1 -and $PinnedPosition -ne 'Before' -and $PSCmdlet.ShouldProcess($pinned.Name, 'DISM /Add-Package')) {
        $steps.Add((Invoke-DismAddPackage -Label ("passe1-epingle-apres-{0}" -f $pinned.Kb) -PackagePath $pinned.Path))
    }
}

New-Item -ItemType File -Force -Path $stopFlag | Out-Null
Wait-Job -Job $sampler -Timeout 30 | Out-Null
Remove-Job -Job $sampler -Force
$freeAfterDism = Get-SystemDriveFreeByte
$samples = @(Import-Csv -Path $samplesPath | ForEach-Object { [int64]$_.OctetsLibres })
$minFreeDuringDism = $freeAfterDism
if ($samples.Count -gt 0) { $minFreeDuringDism = [int64](($samples + $freeAfterDism) | Sort-Object | Select-Object -First 1) }
$storeAfter = Get-ComponentStoreSize -Suffix 'apres'
$disk = [pscustomobject]@{
    Drive                = $env:SystemDrive
    FreeBeforeDownloadGB = [math]::Round($freeBeforeDownload / 1GB, 2)
    FreeBeforeDismGB     = [math]::Round($freeBeforeDism / 1GB, 2)
    MinFreeDuringDismGB  = [math]::Round($minFreeDuringDism / 1GB, 2)
    FreeAfterDismGB      = [math]::Round($freeAfterDism / 1GB, 2)
    DismPeakGB           = [math]::Round(($freeBeforeDism - $minFreeDuringDism) / 1GB, 2)
    DismNetGB            = [math]::Round(($freeBeforeDism - $freeAfterDism) / 1GB, 2)
    Samples              = $samples.Count
    ComponentStoreBefore = $storeBefore
    ComponentStoreAfter  = $storeAfter
}

# 6. Relevé final
$after = Get-OsState
Save-PackageInventory -Suffix 'apres'
$cbs = 'C:\Windows\Logs\CBS\CBS.log'
if (Test-Path $cbs) {
    # CBS.log reste ouvert par le service : copie en lecture partagée, puis compression de la copie.
    try {
        $copy = Join-Path $OutputDirectory 'CBS.log'
        $source = [System.IO.File]::Open($cbs, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $target = [System.IO.File]::Create($copy)
            try { $source.CopyTo($target) } finally { $target.Dispose() }
        } finally { $source.Dispose() }
        Compress-Archive -Path $copy -DestinationPath (Join-Path $OutputDirectory 'CBS.zip') -Force
        Remove-Item -Path $copy
    } catch {
        Write-Host "CBS.log non récupéré : $($_.Exception.Message)"
    }
}

$alreadyUpToDate = ($before.Ubr -ge [int]([regex]::Match($download.EntryTitle, '\.(\d+)\)$').Groups[1].Value))
$result = [pscustomobject]@{
    Kb              = $Kb
    Arch            = $Arch
    EntryTitle      = $download.EntryTitle
    Before          = $before
    After           = $after
    AlreadyUpToDate = $alreadyUpToDate
    Drives          = $drives
    Disk            = $disk
    Steps           = $steps.ToArray()
}
$result | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OutputDirectory 'r02-result.json') -Encoding UTF8

# Résumé lisible dans l'interface GitHub
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-02 : $Kb ($Arch)")
$lines.Add('')
$lines.Add("- Système : $($before.ProductName), $($before.EditionId), $($before.InstallationType), $($before.DisplayVersion)")
$lines.Add("- Build avant : $($before.CurrentBuild).$($before.Ubr) ; après (sans redémarrage) : $($after.CurrentBuild).$($after.Ubr)")
$lines.Add("- Déjà à jour au départ (UBR ≥ celui de l'entrée) : $alreadyUpToDate")
$lines.Add('')
$lines.Add('| Étape | Paquet | Code | Hex | Durée (s) | Redémarrage en attente | UBR après | Message DISM |')
$lines.Add('|---|---|---|---|---|---|---|---|')
foreach ($s in $steps) { $lines.Add("| $($s.Label) | $($s.Package) | $($s.ExitCode) | $($s.ExitCodeHex) | $($s.Seconds) | $($s.RebootPending) | $($s.Ubr) | $($s.Message -replace '\|', '/') |") }
if ($pinned) {
    $lines.Add('')
    $lines.Add("### Paquets $($pinned.Kb) dans la liste DISM après coup")
    $lines.Add('')
    $pinnedLines = @(Get-Content -Path (Join-Path $OutputDirectory 'packages-apres.txt') -Encoding UTF8 | Where-Object { $_ -match $pinned.Kb })
    if ($pinnedLines.Count -eq 0) { $lines.Add('- aucun') }
    foreach ($l in $pinnedLines) { $lines.Add('- `' + ($l -replace '\s+', ' ').Trim() + '`') }
}
$lines.Add('')
$lines.Add("### Espace disque sur $($disk.Drive) (R-12, sans redémarrage)")
$lines.Add('')
$lines.Add("- Libre avant téléchargement : $($disk.FreeBeforeDownloadGB) Go ; avant DISM : $($disk.FreeBeforeDismGB) Go")
$lines.Add("- Minimum pendant DISM : $($disk.MinFreeDuringDismGB) Go ($($disk.Samples) échantillons) ; après DISM : $($disk.FreeAfterDismGB) Go")
$lines.Add("- Pic consommé par DISM : $($disk.DismPeakGB) Go ; consommation nette : $($disk.DismNetGB) Go")
$lines.Add("- Magasin de composants : $($disk.ComponentStoreBefore) avant, $($disk.ComponentStoreAfter) après")
$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
