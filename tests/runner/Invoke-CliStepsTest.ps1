<#
.SYNOPSIS
    Essai sur un runner GitHub Windows 11 ARM64 : étapes réelles de la CLI (Plan, InstallStep, Report) pour .NET et
    Defender, sans cumulative ni redémarrage.

.DESCRIPTION
    Cahier des charges 8.4, 12 (préparation de T1 et T6). Script réservé aux runners GitHub hébergés : il installe des
    mises à jour (DISM en ligne, plateforme et définitions Defender) sur le runner jetable.
      1. configuration de la copie de travail : cible win11-arm64, sans source Office, recherche de la cumulative
         Windows retirée (catalog-queries.json) : seuls .NET, Defender et l'enablement package épinglé sont au dépôt ;
      2. relevé du runner (build, Defender, liste DISM .NET) ;
      3. OffPatch-Cli.ps1 -Action DepotUpdate, puis -Action Plan ;
      4. -Action InstallStep pour chaque étape à installer du plan (lu par Get-OpInstallPlan), dans l'ordre ; une
         étape refusée par la CLI est notée, la suite continue ;
      5. -Action Plan de nouveau (attendu : plus rien à installer hors enablement package), puis -Action Report ;
      6. dans OutputDirectory : sorties et codes, relevés avant et après, manifeste, rapport, journaux (session,
         DISM), state.json archivé.

.EXAMPLE
    .\Invoke-CliStepsTest.ps1 -OutputDirectory $env:RUNNER_TEMP\cli-steps-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script installe des mises à jour : il ne s''exécute que sur un runner GitHub hébergé.'
}
if (-not $PSCmdlet.ShouldProcess('win11-arm64', 'Étapes réelles de la CLI (.NET, Defender)')) { return }

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cli = Join-Path $toolRoot 'app\OffPatch-Cli.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$summary = New-Object System.Collections.Generic.List[string]
$utf8 = New-Object System.Text.UTF8Encoding $false

# 1. Configuration réduite.
$settingsPath = Join-Path $toolRoot 'config\settings.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$settings.targets = @('win11-arm64')
[System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 10), $utf8)
$sourcesPath = Join-Path $toolRoot 'config\office\sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sources.sources = @()
[System.IO.File]::WriteAllText($sourcesPath, ($sources | ConvertTo-Json -Depth 10), $utf8)
$queriesPath = Join-Path $toolRoot 'config\catalog-queries.json'
$queries = Get-Content -LiteralPath $queriesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$queries.targets.'win11-arm64' = @($queries.targets.'win11-arm64' | Where-Object { $_.category -ne 'windows-lcu' })
[System.IO.File]::WriteAllText($queriesPath, ($queries | ConvertTo-Json -Depth 10), $utf8)

# 2. Relevés.
function Get-Snapshot([string]$Name) {
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $mp = $null }
    $net = @(Get-WindowsPackage -Online | Where-Object { $_.PackageName -like 'Package_for_DotNetRollup*' } | ForEach-Object { "$($_.PackageName) $($_.PackageState)" })
    $lines = @(
        "Windows : $((Get-CimInstance -ClassName Win32_OperatingSystem).Caption) $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)"
        $(if ($mp) { "Defender : $($mp.AMRunningMode), plateforme $($mp.AMProductVersion), définitions $($mp.AntivirusSignatureVersion)" } else { 'Defender : Get-MpComputerStatus en échec' })
        ".NET : $($net -join ' ; ')"
    )
    $lines | Set-Content -LiteralPath (Join-Path $OutputDirectory "releve-$Name.txt") -Encoding UTF8
    $summary.Add("Relevé $Name :")
    foreach ($l in $lines) { $summary.Add("- $l") }
    $summary.Add('')
}

function Invoke-Cli([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $OutputDirectory "cli-$Name.txt"
    $started = Get-Date
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments *> $log
    $code = $LASTEXITCODE
    $summary.Add(('- `{0}` : code {1}, {2} s' -f ($Arguments -join ' '), $code, [int]((Get-Date) - $started).TotalSeconds))
    $code
}

$summary.Add('## Étapes réelles de la CLI sur Windows 11 ARM64 (.NET, Defender)')
$summary.Add('')
Get-Snapshot 'avant'

# 3 et 4.
$depotCode = Invoke-Cli 'depot' @('-Action', 'DepotUpdate')
[void](Invoke-Cli 'plan-1' @('-Action', 'Plan'))
$module = Import-Module -Name (Join-Path $toolRoot 'app\module\OffPatch\OffPatch.psd1') -Force -PassThru
$pending = @(& $module { param($Root) Get-OpInstallPlan -Root $Root | Where-Object { $_.State -eq 'Pending' } | ForEach-Object { $_.Id } } $toolRoot)
Remove-Module -ModuleInfo $module
$summary.Add("- étapes à installer : $(if ($pending.Count) { $pending -join ', ' } else { 'aucune' })")
$n = 0
foreach ($id in $pending) {
    $n++
    [void](Invoke-Cli "etape-$n" @('-Action', 'InstallStep', '-StepId', $id))
}

# 5.
[void](Invoke-Cli 'plan-2' @('-Action', 'Plan'))
$reportCode = Invoke-Cli 'report' @('-Action', 'Report')
$summary.Add('')
Get-Snapshot 'apres'

# 6.
$manifest = Join-Path $toolRoot 'depot\manifest.json'
if (Test-Path -LiteralPath $manifest) { Copy-Item -LiteralPath $manifest -Destination $OutputDirectory }
$folders = @{ 'rapports' = Join-Path $toolRoot 'rapports'; 'logs-outil' = Join-Path $toolRoot 'logs'; 'logs-programdata' = Join-Path $env:ProgramData 'OffPatch\logs'; 'temp-programdata' = Join-Path $env:ProgramData 'OffPatch\temp' }
foreach ($name in $folders.Keys) {
    if (Test-Path -LiteralPath $folders[$name]) { Copy-Item -LiteralPath $folders[$name] -Destination (Join-Path $OutputDirectory $name) -Recurse }
}
foreach ($name in 'plan-1', 'plan-2') {
    $summary.Add('')
    $summary.Add("### $name")
    $summary.Add('')
    $summary.Add('```')
    foreach ($line in @(Get-Content -LiteralPath (Join-Path $OutputDirectory "cli-$name.txt"))) { $summary.Add($line) }
    $summary.Add('```')
}
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'resume.md'), ($summary -join "`r`n"), $utf8)
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($summary -join "`r`n") -Encoding UTF8 }
if ($depotCode -ne 0 -or $reportCode -ne 0) { throw "DepotUpdate (code $depotCode) ou Report (code $reportCode) en échec." }
