<#
.SYNOPSIS
    Essai R-15 sur un runner GitHub : suspendre Windows Update le temps d'une session, puis le rétablir.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Relève, sans redémarrage :
      1. état initial des services wuauserv, UsoSvc, WaaSMedicSvc, BITS, TrustedInstaller (état, type de démarrage) ;
      2. arrêt simple de wuauserv (type de démarrage inchangé), puis observation pendant ObserveMinutes :
         le service redémarre-t-il tout seul ?
      3. arrêt de wuauserv et type de démarrage Disabled, observation : le type est-il rétabli (Windows Update
         Medic) et le service redémarre-t-il ?
      4. DISM /Add-Package de l'enablement package épinglé avec wuauserv arrêté et désactivé : code retour ;
      5. rétablissement du type de démarrage et de l'état d'origine, relevé final.
    Aucune analyse ni maintenance du magasin de composants (CLAUDE.md).

.EXAMPLE
    .\Invoke-R15WindowsUpdateTest.ps1 -OutputDirectory $env:RUNNER_TEMP\r15-out -ObserveMinutes 15
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(1, 60)][int]$ObserveMinutes = 15
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$serviceNames = 'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'BITS', 'TrustedInstaller'

function Get-ServiceState {
    foreach ($name in $serviceNames) {
        $cim = Get-CimInstance Win32_Service -Filter "Name='$name'"
        if ($cim) { [pscustomobject]@{ Name = $name; State = $cim.State; StartMode = $cim.StartMode } }
        else { [pscustomobject]@{ Name = $name; State = 'absent'; StartMode = '' } }
    }
}

function Add-StateTable {
    param([string]$Title)
    $lines.Add("### $Title ($(Get-Date -Format 'HH:mm:ss'))")
    $lines.Add('')
    $lines.Add('| Service | État | Démarrage |')
    $lines.Add('|---|---|---|')
    foreach ($s in Get-ServiceState) { $lines.Add("| $($s.Name) | $($s.State) | $($s.StartMode) |") }
    $lines.Add('')
}

function Watch-Wuauserv {
    param([string]$Label)
    $samples = New-Object System.Collections.Generic.List[string]
    $end = (Get-Date).AddMinutes($ObserveMinutes)
    $firstRestart = $null
    $firstModeChange = $null
    $startMode = (Get-CimInstance Win32_Service -Filter "Name='wuauserv'").StartMode
    while ((Get-Date) -lt $end) {
        $cim = Get-CimInstance Win32_Service -Filter "Name='wuauserv'"
        $samples.Add(('{0:HH:mm:ss},{1},{2}' -f (Get-Date), $cim.State, $cim.StartMode))
        if (-not $firstRestart -and $cim.State -ne 'Stopped') { $firstRestart = Get-Date -Format 'HH:mm:ss' }
        if (-not $firstModeChange -and $cim.StartMode -ne $startMode) { $firstModeChange = '{0:HH:mm:ss} ({1})' -f (Get-Date), $cim.StartMode }
        Start-Sleep -Seconds 15
    }
    $samples | Set-Content -Path (Join-Path $OutputDirectory "wuauserv-$Label.csv") -Encoding UTF8
    [pscustomobject]@{ Restart = $firstRestart; ModeChange = $firstModeChange; Samples = $samples.Count }
}

$original = (Get-CimInstance Win32_Service -Filter "Name='wuauserv'")
$originalMode = $original.StartMode
try {
    $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $lines.Add("## R-15 : suspension de Windows Update ($($v.ProductName), $($v.EditionID), $($v.DisplayVersion), $($v.CurrentBuild).$($v.UBR), $env:PROCESSOR_ARCHITECTURE)")
    $lines.Add('')
    Add-StateTable -Title 'État initial'

    # 2. Arrêt simple
    if ($PSCmdlet.ShouldProcess('wuauserv', 'Arrêt simple')) {
        Stop-Service -Name wuauserv -Force
        $w = Watch-Wuauserv -Label 'arret-simple'
        $lines.Add("- Arrêt simple, observation $ObserveMinutes min ($($w.Samples) relevés) : premier redémarrage $(if ($w.Restart) { $w.Restart } else { 'aucun' }) ; type de démarrage modifié : $(if ($w.ModeChange) { $w.ModeChange } else { 'non' })")
        $lines.Add('')
    }

    # 3. Arrêt et désactivation
    if ($PSCmdlet.ShouldProcess('wuauserv', 'Arrêt et type de démarrage Disabled')) {
        Set-Service -Name wuauserv -StartupType Disabled
        Stop-Service -Name wuauserv -Force
        Add-StateTable -Title 'Après arrêt et désactivation'
        $w = Watch-Wuauserv -Label 'desactive'
        $lines.Add("- Arrêt et désactivation, observation $ObserveMinutes min ($($w.Samples) relevés) : premier redémarrage $(if ($w.Restart) { $w.Restart } else { 'aucun' }) ; type de démarrage modifié : $(if ($w.ModeChange) { $w.ModeChange } else { 'non' })")
        $lines.Add('')
    }

    # 4. DISM avec wuauserv arrêté et désactivé
    $pinned = (Get-Content -Path (Join-Path $toolRoot 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items
    $arch = $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() -replace 'amd64', 'x64'
    $url = ($pinned | Where-Object { $_.category -eq 'windows-ekb' -and $_.arch -eq $arch }).url
    $file = Join-Path $env:RUNNER_TEMP ([uri]$url).Segments[-1]
    & curl.exe --fail --silent --show-error --location --retry 3 --output $file $url
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE)" }
    if ($PSCmdlet.ShouldProcess($file, 'DISM /Add-Package avec wuauserv désactivé')) {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        $wuBefore = (Get-Service -Name wuauserv).Status
        $started = Get-Date
        $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
        & $dism /English /Online /Add-Package "/PackagePath:$file" /NoRestart "/LogPath:$(Join-Path $OutputDirectory 'dism-ekb.log')" | Out-File -FilePath (Join-Path $OutputDirectory 'dism-ekb-console.txt') -Encoding UTF8
        $code = $LASTEXITCODE
        $lines.Add(("- DISM /Add-Package de l'enablement package, wuauserv {0} et désactivé avant l'appel : code {1} (0x{1:X8}), {2} s ; wuauserv après l'appel : {3}" -f $wuBefore, $code, [math]::Round(((Get-Date) - $started).TotalSeconds), (Get-Service -Name wuauserv).Status))
        $lines.Add('')
        Add-StateTable -Title 'Après DISM'
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    # 5. Rétablissement : type de démarrage d'origine, puis état d'origine
    $mode = switch ($originalMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { 'Manual' } }
    Set-Service -Name wuauserv -StartupType $mode
    if ($original.State -eq 'Running') { Start-Service -Name wuauserv }
    Add-StateTable -Title "Après rétablissement (type d'origine : $originalMode, état d'origine : $($original.State))"
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
