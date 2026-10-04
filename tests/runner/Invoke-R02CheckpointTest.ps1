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
    Les codes retour de DISM sont relevés, pas jugés : le script n'échoue que sur une erreur imprévue.

.EXAMPLE
    .\Invoke-R02CheckpointTest.ps1 -Kb KB5129195 -Arch arm64 -OutputDirectory $env:RUNNER_TEMP\r02-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^KB\d+$')][string]$Kb,
    [ValidateSet('x64', 'arm64')][string]$Arch = 'arm64',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$WorkDirectory
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
    & dism.exe /English /Online /Add-Package "/PackagePath:$PackagePath" /NoRestart "/LogPath:$log" | Out-File -FilePath $console -Encoding UTF8
    $code = $LASTEXITCODE
    $result = [pscustomobject]@{
        Label         = $Label
        Package       = Split-Path -Leaf $PackagePath
        ExitCode      = $code
        ExitCodeHex   = ('0x{0:X8}' -f $code)
        Seconds       = [math]::Round(((Get-Date) - $started).TotalSeconds)
        RebootPending = (Test-Path $cbsKey)
        Ubr           = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
    }
    Write-Host ("{0} : code {1} ({2}), {3} s, redémarrage en attente : {4}" -f $Label, $result.ExitCode, $result.ExitCodeHex, $result.Seconds, $result.RebootPending)
    $result
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
$download = & (Join-Path $PSScriptRoot 'Save-CatalogEntryFile.ps1') -Kb $Kb -Arch $Arch -Destination $WorkDirectory -ReportPath (Join-Path $OutputDirectory 'download.json') -DiagnosticDirectory $OutputDirectory
$prerequisites = @($download.Files | Where-Object { $_.Role -eq 'prerequisite' } | Sort-Object { [int]($_.Kb -replace '\D', '') })
$target = @($download.Files | Where-Object { $_.Role -eq 'target' })
if ($target.Count -ne 1) { throw "Cible introuvable ou en double pour $Kb dans l'entrée du catalogue." }
$freeAfterDownload = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { '{0} {1} Go' -f $_.DeviceID, [math]::Round($_.FreeSpace / 1GB, 1) })
Write-Host ("Espace libre après téléchargement : {0}" -f ($freeAfterDownload -join ', '))

# 4 et 5. Méthode 1, puis répétition pour le cas « déjà installé »
$steps = New-Object System.Collections.Generic.List[object]
foreach ($pass in 1, 2) {
    foreach ($p in $prerequisites) {
        if ($PSCmdlet.ShouldProcess($p.Name, 'DISM /Add-Package')) {
            $steps.Add((Invoke-DismAddPackage -Label ("passe{0}-prerequis-{1}" -f $pass, $p.Kb) -PackagePath $p.Path))
        }
    }
    if ($PSCmdlet.ShouldProcess($target[0].Name, 'DISM /Add-Package')) {
        $steps.Add((Invoke-DismAddPackage -Label ("passe{0}-cible-{1}" -f $pass, $target[0].Kb) -PackagePath $target[0].Path))
    }
}

# 6. Relevé final
$after = Get-OsState
Save-PackageInventory -Suffix 'apres'
$cbs = 'C:\Windows\Logs\CBS\CBS.log'
if (Test-Path $cbs) { Compress-Archive -Path $cbs -DestinationPath (Join-Path $OutputDirectory 'CBS.zip') -Force }

$alreadyUpToDate = ($before.Ubr -ge [int]([regex]::Match($download.EntryTitle, '\.(\d+)\)$').Groups[1].Value))
$result = [pscustomobject]@{
    Kb              = $Kb
    Arch            = $Arch
    EntryTitle      = $download.EntryTitle
    Before          = $before
    After           = $after
    AlreadyUpToDate = $alreadyUpToDate
    Drives          = $drives
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
$lines.Add('| Étape | Paquet | Code | Hex | Durée (s) | Redémarrage en attente |')
$lines.Add('|---|---|---|---|---|---|')
foreach ($s in $steps) { $lines.Add("| $($s.Label) | $($s.Package) | $($s.ExitCode) | $($s.ExitCodeHex) | $($s.Seconds) | $($s.RebootPending) |") }
$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
