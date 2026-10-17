<#
.SYNOPSIS
    Essai T3 sur un runner GitHub Windows 11 ARM64 : actions Plan et Report de la CLI sur un PC réel, en lecture
    seule, avec ou sans dépôt téléchargé.

.DESCRIPTION
    Cahier des charges 12, T3 (« Windows 11 25H2 déjà à jour : rien à installer, rapport cohérent »). Script réservé
    aux runners GitHub hébergés. Aucune installation : seules les actions DepotUpdate, Plan et Report sont lancées.
      1. configuration de la copie de travail réduite à la cible win11-arm64, sans source Office (settings.json,
         office\sources.json) ;
      2. relevé du runner : build et UBR, Defender (Get-MpComputerStatus), Office Click-to-Run ;
      3. OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly (catalogue interrogé, rien téléchargé) ;
      4. avec -Download seulement : OffPatch-Cli.ps1 -Action DepotUpdate (cumulative, .NET, Defender, enablement
         package de la cible) ;
      5. OffPatch-Cli.ps1 -Action Plan, puis -Action Report ;
      6. dans OutputDirectory : sortie de chaque action et son code, relevé, manifeste, rapport HTML, journaux.

.EXAMPLE
    .\Invoke-T3PlanTest.ps1 -OutputDirectory $env:RUNNER_TEMP\t3-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$Download
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie la configuration de la copie de travail et peut télécharger plusieurs gigaoctets : il ne s''exécute que sur un runner GitHub hébergé.'
}
if (-not $PSCmdlet.ShouldProcess('win11-arm64', 'Essai T3 (Plan et Report)')) { return }

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cli = Join-Path $toolRoot 'app\OffPatch-Cli.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$summary = New-Object System.Collections.Generic.List[string]

# 1. Configuration réduite à la cible du runner.
$utf8 = New-Object System.Text.UTF8Encoding $false
$settingsPath = Join-Path $toolRoot 'config\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$settings.targets = @('win11-arm64')
[System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $utf8)
$sourcesPath = Join-Path $toolRoot 'config\office\sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sources.sources = @()
[System.IO.File]::WriteAllText($sourcesPath, ($sources | ConvertTo-Json -Depth 10), $utf8)

# 2. Relevé du runner.
$cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$mp = $null
try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
$c2r = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
$summary.Add('## Essai T3 : Plan et Report sur Windows 11 ARM64')
$summary.Add('')
$summary.Add("- Windows : $((Get-CimInstance -ClassName Win32_OperatingSystem).Caption) $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR), $env:PROCESSOR_ARCHITECTURE")
if ($mp) { $summary.Add("- Defender : $($mp.AMRunningMode), plateforme $($mp.AMProductVersion), définitions $($mp.AntivirusSignatureVersion)") } else { $summary.Add('- Defender : Get-MpComputerStatus en échec') }
if ($c2r) { $summary.Add("- Office Click-to-Run : $($c2r.ProductReleaseIds), $($c2r.VersionToReport), $($c2r.Platform)") } else { $summary.Add('- Office Click-to-Run : absent') }
$summary.Add("- Dépôt téléchargé : $([bool]$Download)")
$summary.Add('')

# 3 à 5. Actions de la CLI, chacune dans un PowerShell enfant, sortie gardée.
function Invoke-Cli([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $OutputDirectory "cli-$Name.txt"
    $started = Get-Date
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments *> $log
    $code = $LASTEXITCODE
    $summary.Add(('- `{0}` : code {1}, {2} s' -f ($Arguments -join ' '), $code, [int]((Get-Date) - $started).TotalSeconds))
    $code
}
[void](Invoke-Cli 'list' @('-Action', 'DepotUpdate', '-ListOnly'))
if ($Download) { [void](Invoke-Cli 'depot' @('-Action', 'DepotUpdate')) }
$planCode = Invoke-Cli 'plan' @('-Action', 'Plan')
$reportCode = Invoke-Cli 'report' @('-Action', 'Report')

# 6. Pièces.
$manifest = Join-Path $toolRoot 'depot\manifest.json'
if (Test-Path -LiteralPath $manifest) { Copy-Item -LiteralPath $manifest -Destination $OutputDirectory }
$folders = @{ 'rapports' = Join-Path $toolRoot 'rapports'; 'logs-outil' = Join-Path $toolRoot 'logs'; 'logs-programdata' = Join-Path $env:ProgramData 'OffPatch\logs' }
foreach ($name in $folders.Keys) {
    if (Test-Path -LiteralPath $folders[$name]) { Copy-Item -LiteralPath $folders[$name] -Destination (Join-Path $OutputDirectory $name) -Recurse }
}
$summary.Add('')
$summary.Add('### Plan')
$summary.Add('')
$summary.Add('```')
foreach ($line in @(Get-Content -LiteralPath (Join-Path $OutputDirectory 'cli-plan.txt') -Encoding Default)) { $summary.Add($line) }
$summary.Add('```')
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'resume.md'), ($summary -join "`r`n"), $utf8)
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($summary -join "`r`n") -Encoding UTF8 }
if ($planCode -ne 0 -or $reportCode -ne 0) { throw "Plan (code $planCode) ou Report (code $reportCode) en échec." }
