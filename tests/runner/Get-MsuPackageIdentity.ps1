<#
.SYNOPSIS
    Ouvre des fichiers .msu et relève l'identité des paquets qu'ils contiennent, puis la compare aux paquets installés.

.DESCRIPTION
    Script réservé aux runners GitHub (R-05, R-09). Pour chaque lien autorisé : téléchargement, liste du contenu du .msu
    (expand.exe), extraction des fichiers update.mum des .cab, lecture du nom et de la version du paquet
    (assemblyIdentity). Relève ensuite, en lecture seule, les paquets installés (dism /Get-Packages) et Get-HotFix,
    pour vérifier si la version inscrite dans le .msu se retrouve dans la liste DISM d'un PC à jour.
    N'installe rien.

.EXAMPLE
    .\Get-MsuPackageIdentity.ps1 -Url 'https://catalog.sf.dl.delivery.mp.microsoft.com/…/windows11.0-kb5126052-x64-ndp481_<sha1>.msu' -OutputDirectory D:\out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Url,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string[]]$AllowedHost = @('catalog.sf.dl.delivery.mp.microsoft.com', 'catalog.s.download.windowsupdate.com')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'msu-inspect'
if (-not $env:RUNNER_TEMP) { $work = Join-Path $OutputDirectory 'work' }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Identité des paquets .msu ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')
$lines.Add('| Fichier .msu | Contenu | Paquet (update.mum) | Version |')
$lines.Add('|---|---|---|---|')

foreach ($u in $Url) {
    $uri = [uri]$u
    if ($uri.Scheme -ne 'https' -or $AllowedHost -notcontains $uri.Host) { throw "Domaine non autorisé : $($uri.Host)" }
    $name = $uri.Segments[-1]
    $msu = Join-Path $work $name
    & curl.exe --fail --silent --show-error --location --retry 3 --output $msu $u
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour $name" }

    $content = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($name))
    New-Item -ItemType Directory -Force -Path $content | Out-Null
    & expand.exe "-F:*" $msu $content | Out-Null
    $entries = @(Get-ChildItem -Path $content -File | Select-Object -ExpandProperty Name)
    Write-Host "$name : $($entries -join ', ')"

    $found = $false
    foreach ($cab in Get-ChildItem -Path $content -Filter '*.cab' -File) {
        if ($cab.Name -match '(?i)^wsusscan') { continue }
        $mumFolder = Join-Path $content ($cab.BaseName + '-mum')
        New-Item -ItemType Directory -Force -Path $mumFolder | Out-Null
        & expand.exe '-F:update.mum' $cab.FullName $mumFolder | Out-Null
        $mum = Join-Path $mumFolder 'update.mum'
        if (Test-Path $mum) {
            [xml]$xml = Get-Content -Path $mum -Raw
            $identity = $xml.assembly.assemblyIdentity
            Write-Host "  $($cab.Name) : $($identity.name) $($identity.version)"
            $lines.Add("| $name | $($entries -join ', ') | $($identity.name) | $($identity.version) |")
            $found = $true
        }
    }
    if (-not $found) { $lines.Add("| $name | $($entries -join ', ') | (pas de update.mum lisible) | |") }
}

$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
$lines.Add('')
$lines.Add("Système : $($v.CurrentBuild).$($v.UBR), .NET Framework 4 Release = $release")
$lines.Add('')
$lines.Add('Paquets installés liés à .NET (dism /Get-Packages) :')
$lines.Add('')
$dism = & dism.exe /English /Online /Get-Packages /Format:Table
$dism | Out-File -FilePath (Join-Path $OutputDirectory 'packages.txt') -Encoding UTF8
foreach ($l in ($dism | Select-String -Pattern 'DotNet|NetFx|NDP')) { $lines.Add('    ' + $l.Line.Trim()) }
$lines.Add('')
$lines.Add('Get-HotFix :')
$lines.Add('')
foreach ($h in (Get-HotFix | Sort-Object HotFixID)) { $lines.Add("    $($h.HotFixID) $($h.Description) $($h.InstalledOn)") }

$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
