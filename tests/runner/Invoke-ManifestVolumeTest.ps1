<#
.SYNOPSIS
    Essai sur un runner GitHub : écriture atomique du manifeste (Save-OpManifest) sur un volume exFAT et sur un
    volume NTFS.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système (disques virtuels) : ne jamais
    l'exécuter ailleurs. Pour chaque système de fichiers : disque virtuel de 64 Mo créé par diskpart (create vdisk,
    attach, create partition, format quick, assign), puis, sur ce volume, premier enregistrement du manifeste (pas de
    fichier existant : File.Move), relecture, remplacement (File.Replace), relecture, contrôle qu'aucun fichier
    temporaire ne reste. Le disque virtuel est détaché à la fin. Manifeste de fixture (tests/Fixtures/manifest).

.EXAMPLE
    .\Invoke-ManifestVolumeTest.ps1 -OutputDirectory $env:RUNNER_TEMP\manifest-volume-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Test-OpManifest', 'Read-OpManifest', 'Save-OpManifest') {
    . (Join-Path $toolRoot "app\module\OffPatch\Private\$name.ps1")
}
$fixture = Join-Path $toolRoot 'tests\Fixtures\manifest\manifest-valide.json'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Manifeste : écriture atomique sur exFAT et NTFS ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')
$lines.Add('| Système de fichiers | Volume | Premier enregistrement | Relecture | Remplacement | Relecture | Fichier temporaire restant |')
$lines.Add('|---|---|---|---|---|---|---|')

function Invoke-DiskPart {
    param([string[]]$Command, [string]$Label)
    $script = Join-Path $env:RUNNER_TEMP "diskpart-$Label.txt"
    $Command | Set-Content -Path $script -Encoding ASCII
    $output = & diskpart.exe /s $script
    $output | Out-File -FilePath (Join-Path $OutputDirectory "diskpart-$Label.txt") -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "diskpart a échoué ($LASTEXITCODE) : $Label" }
}

foreach ($case in @(@('exfat', 'R'), @('ntfs', 'S'))) {
    $fs = $case[0]
    $letter = $case[1]
    $vhd = Join-Path $env:RUNNER_TEMP "manifeste-$fs.vhdx"
    $row = @{ First = 'non fait'; Read1 = 'non fait'; Replace = 'non fait'; Read2 = 'non fait'; Temp = '?'; Volume = '' }
    try {
        if (-not $PSCmdlet.ShouldProcess($vhd, "Disque virtuel $fs")) { continue }
        Invoke-DiskPart -Label "$fs-creation" -Command @(
            "create vdisk file=""$vhd"" maximum=64 type=expandable",
            "select vdisk file=""$vhd""",
            'attach vdisk',
            'create partition primary',
            "format fs=$fs quick label=OFFPATCH",
            "assign letter=$letter"
        )
        $volume = Get-Volume -DriveLetter $letter
        $row.Volume = "$($letter): $($volume.FileSystem)"
        $target = "$($letter):\OffPatch\depot\manifest.json"

        $manifest = Read-OpJsonFile -Path $fixture
        try { Save-OpManifest -Manifest $manifest -Path $target -ToolVersion '0.1.0'; $row.First = 'réussi (File.Move)' } catch { $row.First = "échec : $($_.Exception.Message)" }
        try { $row.Read1 = "$(@((Read-OpManifest -Path $target).items).Count) éléments" } catch { $row.Read1 = "échec : $($_.Exception.Message)" }
        $manifest = Read-OpJsonFile -Path $fixture
        $manifest.items = @($manifest.items[0])
        try { Save-OpManifest -Manifest $manifest -Path $target; $row.Replace = 'réussi (File.Replace)' } catch { $row.Replace = "échec : $($_.Exception.Message)" }
        try { $row.Read2 = "$(@((Read-OpManifest -Path $target).items).Count) élément(s)" } catch { $row.Read2 = "échec : $($_.Exception.Message)" }
        $row.Temp = [string](Test-Path ($target + '.tmp'))
    } catch {
        $row.First = "ERREUR : $($_.Exception.Message)"
    } finally {
        if (Test-Path $vhd) {
            try { Invoke-DiskPart -Label "$fs-detachement" -Command @("select vdisk file=""$vhd""", 'detach vdisk') } catch { Write-Host "Détachement : $($_.Exception.Message)" }
        }
        $lines.Add("| $fs | $($row.Volume) | $($row.First) | $($row.Read1) | $($row.Replace) | $($row.Read2) | $($row.Temp) |")
    }
}

$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
if ($summary -match '\| (échec|ERREUR)') { throw 'Au moins une opération a échoué : voir le résumé.' }
