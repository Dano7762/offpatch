<#
.SYNOPSIS
    Essai R-14 sur un runner GitHub : codes retour de dism.exe et comportement d'Add-WindowsPackage sur des cas limites.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Petits paquets seulement (aucune cumulative) : enablement package et SSU épinglés (config/pinned-items.json),
    cumulatives .NET Windows 11 du mois (x64 et ARM64, recherche au catalogue). Cas, tous avec /NoRestart :
      - paquet .NET de la bonne architecture (déjà installé ou à installer) ;
      - paquet .NET d'une autre architecture ;
      - SSU Windows 10 x64 sur ce Windows 11 ;
      - enablement package (3010 attendu, R-03), par dism.exe puis par Add-WindowsPackage ;
      - copie du .msu de l'enablement package avec un octet inversé ;
      - chemin inexistant.
    Chaque cas passe par dism.exe /English /Online /Add-Package, puis, pour comparaison, par Add-WindowsPackage
    -Online -NoRestart (objet renvoyé, RestartNeeded, ou exception et HResult). Rien n'est jugé : tout est relevé.
    Aucune analyse ni maintenance du magasin de composants (CLAUDE.md).
    Scénario Concurrent : deux dism.exe /Add-Package lancés presque en même temps (cumulative .NET de la bonne
    architecture, puis enablement package 5 s après) ; relève le code, la durée et le message du second, pour savoir
    si DISM attend ou échoue quand une autre opération de maintenance est en cours.

.EXAMPLE
    .\Invoke-R14DismTest.ps1 -OutputDirectory $env:RUNNER_TEMP\r14-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('Cases', 'Concurrent')][string]$Scenario = 'Cases'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($name in 'ConvertFrom-OpCatalogSearchPage', 'ConvertFrom-OpCatalogDownloadDialog', 'Find-OpCatalogUpdate') {
    . (Join-Path $toolRoot "app\module\OffPatch\Private\$name.ps1")
}
$cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$arch = $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() -replace 'amd64', 'x64'
$otherArch = if ($arch -eq 'arm64') { 'x64' } else { 'arm64' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r14-work'
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Get-DialogUrl {
    param([string]$UpdateId)
    $body = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]')
    $dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing).Content
    @(ConvertFrom-OpCatalogDownloadDialog -Html $dialog | ForEach-Object { $_.Url })
}

function Save-File {
    param([string]$Url)
    $file = Join-Path $work ([uri]$Url).Segments[-1]
    & curl.exe --fail --silent --show-error --location --retry 3 --output $file $Url
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) : $Url" }
    $signature = Get-AuthenticodeSignature -FilePath $file
    if ($signature.Status -ne 'Valid') { throw "Signature non valide pour $file : $($signature.Status)" }
    $file
}

function Invoke-Case {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Label, [string]$PackagePath)
    $results = New-Object System.Collections.Generic.List[object]
    if (-not $PSCmdlet.ShouldProcess($PackagePath, "DISM /Add-Package ($Label)")) { return }

    # dism.exe
    $log = Join-Path $OutputDirectory "dism-$Label.log"
    $started = Get-Date
    $output = @(& dism.exe /English /Online /Add-Package "/PackagePath:$PackagePath" /NoRestart "/LogPath:$log")
    $code = $LASTEXITCODE
    $output | Out-File -FilePath (Join-Path $OutputDirectory "dism-$Label-console.txt") -Encoding UTF8
    $message = @($output | ForEach-Object { "$_".Trim() } | Where-Object {
            $_ -and $_ -notmatch '^\[[= ]*[\d.]*%?[= ]*\]$' -and $_ -notmatch '^(Deployment Image Servicing|Version:|Image Version:|HOTPATCHUTIL )'
        }) -join ' / '
    $results.Add([pscustomobject]@{
            Case = $Label; Tool = 'dism.exe'; Code = $code; Hex = ('0x{0:X8}' -f $code)
            RestartNeeded = $null; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds); RebootPending = (Test-Path $cbsKey); Message = $message
        })

    # Add-WindowsPackage, même paquet
    $started = Get-Date
    try {
        $object = Add-WindowsPackage -Online -PackagePath $PackagePath -NoRestart -LogPath (Join-Path $OutputDirectory "addwindowspackage-$Label.log") -ErrorAction Stop
        $results.Add([pscustomobject]@{
                Case = $Label; Tool = 'Add-WindowsPackage'; Code = 0; Hex = $null
                RestartNeeded = $object.RestartNeeded; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds); RebootPending = (Test-Path $cbsKey); Message = 'objet renvoyé'
            })
    } catch {
        $hresult = $_.Exception.HResult
        $results.Add([pscustomobject]@{
                Case = $Label; Tool = 'Add-WindowsPackage'; Code = $hresult; Hex = ('0x{0:X8}' -f $hresult)
                RestartNeeded = $null; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds); RebootPending = (Test-Path $cbsKey)
                Message = ('{0} : {1}' -f $_.Exception.GetType().Name, ($_.Exception.Message -replace '\s+', ' ').Trim())
            })
    }
    foreach ($r in $results) { Write-Host ("{0} / {1} : code {2} {3}, RestartNeeded {4}, {5} s - {6}" -f $r.Case, $r.Tool, $r.Code, $r.Hex, $r.RestartNeeded, $r.Seconds, $r.Message) }
    $results.ToArray()
}

$lines = New-Object System.Collections.Generic.List[string]
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$lines.Add("## R-14 : dism.exe et Add-WindowsPackage ($($v.ProductName), $($v.DisplayVersion), $($v.CurrentBuild).$($v.UBR), $arch)")
$lines.Add('')
$all = New-Object System.Collections.Generic.List[object]
try {
    $pinned = (Get-Content -Path (Join-Path $toolRoot 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items
    $ekb = Save-File -Url ($pinned | Where-Object { $_.category -eq 'windows-ekb' -and $_.arch -eq $arch }).url
    $ssu = Save-File -Url ($pinned | Where-Object { $_.category -eq 'windows-ssu' }).url
    $net = @{}
    foreach ($a in $arch, $otherArch) {
        $entry = Find-OpCatalogUpdate -Query 'Cumulative Update for .NET Framework Windows 11, version 24H2' |
            Where-Object { $_.Title -match "for Windows 11, version 24H2 for $a \(" -and $_.Title -notmatch 'Preview' } |
            Sort-Object LastUpdated -Descending | Select-Object -First 1
        $net[$a] = Save-File -Url (Get-DialogUrl -UpdateId $entry.UpdateId | Select-Object -First 1)
    }
    $corrupt = Join-Path $work 'corrompu\ekb-corrompu.msu'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $corrupt) | Out-Null
    Copy-Item -Path $ekb -Destination $corrupt
    $bytes = [System.IO.File]::ReadAllBytes($corrupt)
    $middle = [int]($bytes.Length / 2)
    $bytes[$middle] = [byte](255 - $bytes[$middle])
    [System.IO.File]::WriteAllBytes($corrupt, $bytes)

    if ($Scenario -eq 'Concurrent') {
        $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
        $first = Start-Process -FilePath $dism -ArgumentList '/English', '/Online', '/Add-Package', "/PackagePath:$($net[$arch])", '/NoRestart', "/LogPath:$(Join-Path $OutputDirectory 'dism-concurrent-1.log')" -RedirectStandardOutput (Join-Path $OutputDirectory 'dism-concurrent-1-console.txt') -NoNewWindow -PassThru
        Start-Sleep -Seconds 5
        $started = Get-Date
        $second = Start-Process -FilePath $dism -ArgumentList '/English', '/Online', '/Add-Package', "/PackagePath:$ekb", '/NoRestart', "/LogPath:$(Join-Path $OutputDirectory 'dism-concurrent-2.log')" -RedirectStandardOutput (Join-Path $OutputDirectory 'dism-concurrent-2-console.txt') -NoNewWindow -PassThru
        $second.WaitForExit()
        $secondSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
        $firstRunningAtEnd = -not $first.HasExited
        $first.WaitForExit()
        foreach ($p in @(@('premier (.NET)', $first, 1), @('second (enablement package)', $second, 2))) {
            $console = @(Get-Content -Path (Join-Path $OutputDirectory "dism-concurrent-$($p[2])-console.txt") | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^\[[= ]*[\d.]*%?[= ]*\]$' -and $_ -notmatch '^(Deployment Image Servicing|Version:|Image Version:|HOTPATCHUTIL )' }) -join ' / '
            $all.Add([pscustomobject]@{ Case = "concurrent-$($p[0])"; Tool = 'dism.exe'; Code = $p[1].ExitCode; Hex = ('0x{0:X8}' -f $p[1].ExitCode); RestartNeeded = $null; Seconds = $null; RebootPending = (Test-Path $cbsKey); Message = $console })
        }
        $lines.Add("- Second DISM lancé 5 s après le premier : terminé en $secondSeconds s ; premier DISM encore en cours à la fin du second : $firstRunningAtEnd")
        $lines.Add('')
        return
    }

    foreach ($case in @(
            @("net-$arch", $net[$arch]),
            @("net-$otherArch-autre-architecture", $net[$otherArch]),
            @('ssu-windows10-x64', $ssu),
            @('ekb', $ekb),
            @('ekb-corrompu', $corrupt),
            @('chemin-absent', (Join-Path $work 'absent\inexistant.msu'))
        )) {
        foreach ($r in @(Invoke-Case -Label $case[0] -PackagePath $case[1])) { $all.Add($r) }
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    $lines.Add('| Cas | Outil | Code | Hex | RestartNeeded | Durée (s) | Redémarrage en attente | Message |')
    $lines.Add('|---|---|---|---|---|---|---|---|')
    foreach ($r in $all) { $lines.Add("| $($r.Case) | $($r.Tool) | $($r.Code) | $($r.Hex) | $($r.RestartNeeded) | $($r.Seconds) | $($r.RebootPending) | $($r.Message -replace '\|', '/') |") }
    $all | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $OutputDirectory 'r14-result.json') -Encoding UTF8
    & dism.exe /English /Online /Get-Packages /Format:Table | Out-File -FilePath (Join-Path $OutputDirectory 'packages-apres.txt') -Encoding UTF8
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
