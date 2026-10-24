<#
.SYNOPSIS
    Essai T8 sur un runner GitHub Windows Server 2025 : préparation d'un support sur trois disques virtuels (FAT32,
    exFAT, NTFS), refus attendu en FAT32.

.DESCRIPTION
    Cahier des charges 12, T8 (« Préparation d'un support en FAT32 : refus avec message explicite »). Script réservé
    aux runners GitHub hébergés : il crée et monte des disques virtuels avec diskpart.
      1. configuration de la copie de travail réduite à la cible win11-x64, sans source Office ; dépôt synthétique
         d'un élément (fichier aléatoire de 8 Mo, manifeste conforme à 7.2), rien n'est téléchargé ;
      2. pour chaque système de fichiers : disque virtuel de 1 Go formaté et monté sur une lettre libre ;
      3. OffPatch-Cli.ps1 -Action Support -Destination <lecteur> -WhatIf : plan, refus et code de sortie ;
      4. exFAT et NTFS seulement : Copy-OpSupport puis Test-OpSupport (copie réelle, tailles et SHA-256) ;
      5. disques démontés ; dans OutputDirectory : sortie de chaque action, résumé, journaux.
    Attendu : FAT32 refusé (code 1, « Système de fichiers FAT32 refusé ») ; exFAT et NTFS acceptés, copiés et
    vérifiés.

.EXAMPLE
    .\Invoke-T8SupportTest.ps1 -OutputDirectory $env:RUNNER_TEMP\t8-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script crée des disques virtuels avec diskpart et modifie la copie de travail : il ne s''exécute que sur un runner GitHub hébergé.'
}
if (-not $PSCmdlet.ShouldProcess('FAT32, exFAT, NTFS', 'Essai T8 (préparation de supports)')) { return }

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cli = Join-Path $toolRoot 'app\OffPatch-Cli.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$summary = New-Object System.Collections.Generic.List[string]
$failures = New-Object System.Collections.Generic.List[string]

# 1. Configuration réduite et dépôt synthétique.
$utf8 = New-Object System.Text.UTF8Encoding $false
$settingsPath = Join-Path $toolRoot 'config\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$settings.targets = @('win11-x64')
[System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $utf8)
$sourcesPath = Join-Path $toolRoot 'config\office\sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sources.sources = @()
[System.IO.File]::WriteAllText($sourcesPath, ($sources | ConvertTo-Json -Depth 10), $utf8)

$bytes = New-Object byte[] 8MB
(New-Object System.Random).NextBytes($bytes)
$staging = Join-Path $toolRoot 'depot\t8-donnees.bin'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $staging) | Out-Null
[System.IO.File]::WriteAllBytes($staging, $bytes)
$sha = (Get-FileHash -LiteralPath $staging -Algorithm SHA256).Hash.ToLowerInvariant()
$folder = Join-Path $toolRoot "depot\files\$sha"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
Move-Item -LiteralPath $staging -Destination (Join-Path $folder 't8-donnees.bin')
$manifest = '{ "schemaVersion": 1, "generatedAt": "2026-10-24T08:00:00Z", "toolVersion": "0.6.0", "items": [ { "id": "win11-x64-defender-t8", "category": "defender", "target": { "os": "win11", "arch": "x64" }, "order": 1, "requiresReboot": false, "files": [ { "path": "files/' + $sha + '/t8-donnees.bin", "sha256": "' + $sha + '", "size": ' + $bytes.Length + ' } ] } ] }'
[System.IO.File]::WriteAllText((Join-Path $toolRoot 'depot\manifest.json'), $manifest, $utf8)

Import-Module (Join-Path $toolRoot 'app\module\OffPatch\OffPatch.psd1') -Force
$summary.Add('## Essai T8 : préparation d''un support selon le système de fichiers')
$summary.Add('')
$summary.Add("- Windows : $((Get-CimInstance -ClassName Win32_OperatingSystem).Caption), outil sur $([System.IO.Path]::GetPathRoot($toolRoot))")
$summary.Add('- Dépôt synthétique : 1 élément win11-x64, 8 Mo')
$summary.Add('')

function Invoke-DiskPart([string]$Name, [string[]]$Lines) {
    $script = Join-Path $OutputDirectory "diskpart-$Name.txt"
    [System.IO.File]::WriteAllLines($script, $Lines)
    $out = & diskpart.exe /s $script
    Add-Content -LiteralPath (Join-Path $OutputDirectory "diskpart-$Name.log") -Value $out
    if ($LASTEXITCODE -ne 0) { throw "diskpart ($Name) : code $LASTEXITCODE`n$($out -join "`n")" }
}

$used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
$letters = @('R', 'S', 'T', 'U', 'V', 'W' | Where-Object { $used -notcontains $_ })
$cases = @(
    @{ FileSystem = 'FAT32'; Format = 'fat32'; Accept = $false },
    @{ FileSystem = 'exFAT'; Format = 'exfat'; Accept = $true },
    @{ FileSystem = 'NTFS'; Format = 'ntfs'; Accept = $true })
$i = 0
foreach ($case in $cases) {
    $fs = $case.FileSystem
    $letter = $letters[$i]
    $i++
    $vhd = Join-Path $env:RUNNER_TEMP "t8-$fs.vhdx"
    $drive = "${letter}:\"
    $summary.Add("### $fs ($drive)")
    $summary.Add('')
    Invoke-DiskPart "creation-$fs" @(
        "create vdisk file=`"$vhd`" maximum=1024 type=expandable", "select vdisk file=`"$vhd`"", 'attach vdisk',
        'create partition primary', "format fs=$($case.Format) quick label=T8$fs", "assign letter=$letter")
    try {
        $volume = New-Object System.IO.DriveInfo $drive
        $summary.Add("- Volume : $($volume.DriveFormat), $([math]::Round($volume.TotalSize / 1MB)) Mo, $($volume.DriveType)")

        $log = Join-Path $OutputDirectory "cli-support-$fs.txt"
        & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli -Action Support -Destination $drive -WhatIf *> $log
        $code = $LASTEXITCODE
        $text = (Get-Content -LiteralPath $log) -join "`n"
        $summary.Add("- ``-Action Support -WhatIf`` : code $code")
        $summary.Add('')
        $summary.Add('```')
        $summary.Add($text)
        $summary.Add('```')
        # Sortie de l'enfant relue dans la page de code de la console : « . » à la place des lettres accentuées.
        $refused = $text -match "Refus : Syst.me de fichiers $fs refus. : NTFS ou exFAT requis"
        if ($case.Accept) {
            if ($code -ne 0 -or $text -match 'Refus :') { $failures.Add("$fs : plan refusé alors qu'il devait être accepté (code $code).") }
            else {
                $copy = Copy-OpSupport -Destination $drive -Root $toolRoot -Confirm:$false
                $check = Test-OpSupport -Destination $drive -Root $toolRoot
                $summary.Add("- Copie : $(@($copy.Folders).Count) dossier(s), annulée : $($copy.Cancelled) ; vérification : $(if ($check.Ok) { 'conforme' } else { 'écarts' }), $($check.FileCount) fichier(s) du dépôt")
                foreach ($p in $check.Problems) { $summary.Add("  - $p") }
                if ($copy.Cancelled -or -not $check.Ok) { $failures.Add("$fs : copie ou vérification en échec.") }
            }
        } elseif ($code -ne 1 -or -not $refused) {
            $failures.Add("$fs : refus explicite attendu (code 1, « Système de fichiers $fs refusé »), obtenu code $code.")
        } elseif (Test-Path -LiteralPath (Join-Path $drive 'offpatch.root')) {
            $failures.Add("$fs : refus annoncé, mais des fichiers ont été écrits sur le support.")
        }
    } finally {
        Invoke-DiskPart "retrait-$fs" @("select vdisk file=`"$vhd`"", 'detach vdisk')
    }
    $summary.Add('')
}

$folders = @{ 'logs-outil' = Join-Path $toolRoot 'logs'; 'logs-programdata' = Join-Path $env:ProgramData 'OffPatch\logs' }
foreach ($name in $folders.Keys) {
    if (Test-Path -LiteralPath $folders[$name]) { Copy-Item -LiteralPath $folders[$name] -Destination (Join-Path $OutputDirectory $name) -Recurse }
}
$summary.Add('### Résultat')
$summary.Add('')
if ($failures.Count -eq 0) { $summary.Add('Conforme : FAT32 refusé avec message explicite, exFAT et NTFS préparés et vérifiés.') }
foreach ($f in $failures) { $summary.Add("- $f") }
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'resume.md'), ($summary -join "`r`n"), $utf8)
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($summary -join "`r`n") -Encoding UTF8 }
if ($failures.Count -gt 0) { throw "Essai T8 non conforme : $($failures -join ' ')" }
