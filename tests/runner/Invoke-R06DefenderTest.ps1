<#
.SYNOPSIS
    Essai R-06 sur un runner GitHub : application de mpam-fe.exe sur une plateforme Defender d'origine.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
      1. état de Defender (Get-MpComputerStatus) et antivirus enregistrés (SecurityCenter2, poste client) ;
      2. téléchargement de mpam-fe.exe par le lien officiel, version du fichier et signature ;
      3. simulation d'une installation récente : MpCmdRun -ResetPlatform (plateforme de l'image), et -RemoveDefinitions -All si demandé ;
      4. si -PlatformUrl est donné : installation de la mise à jour de plateforme (KB4052623, updateplatform.*.exe), puis attente du retour de Defender ;
      5. application de mpam-fe.exe selon -Variant : avec -q, sans argument, ou -q puis sans argument si -q échoue ; code retour et durée ;
      6. état final : la version des définitions doit être celle du fichier.
    Les résultats sont relevés, pas jugés : le script n'échoue que sur une erreur imprévue.

.EXAMPLE
    .\Invoke-R06DefenderTest.ps1 -Arch x64 -OutputDirectory $env:RUNNER_TEMP\r06-out
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingBrokenHashAlgorithms', '', Justification = 'SHA-1 imposé par le nom de fichier du catalogue : comparaison d''empreinte, pas un contrôle de sécurité.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DownloadUrl = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch={0}',
    [ValidateSet('QuietThenPlain', 'Quiet', 'Plain')][string]$Variant = 'QuietThenPlain',
    [switch]$RemoveDefinitions,
    [string]$PlatformUrl
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$lines = New-Object System.Collections.Generic.List[string]

function Get-DefenderState {
    param([string]$Label)
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        $state = [pscustomobject]@{
            Label             = $Label
            AMRunningMode     = $s.AMRunningMode
            AMServiceEnabled  = $s.AMServiceEnabled
            AntivirusEnabled  = $s.AntivirusEnabled
            RealTime          = $s.RealTimeProtectionEnabled
            Platform          = $s.AMProductVersion
            Engine            = $s.AMEngineVersion
            Signatures        = $s.AntivirusSignatureVersion
            SignaturesUpdated = $s.AntivirusSignatureLastUpdated
        }
    } catch {
        $state = [pscustomobject]@{ Label = $Label; AMRunningMode = "Erreur : $($_.Exception.Message)"; AMServiceEnabled = $null; AntivirusEnabled = $null; RealTime = $null; Platform = $null; Engine = $null; Signatures = $null; SignaturesUpdated = $null }
    }
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f $state.Label, $state.AMRunningMode, $state.AntivirusEnabled, $state.RealTime, $state.Platform, $state.Engine, $state.Signatures, $state.SignaturesUpdated))
    $state
}

function Wait-DefenderNormal {
    param([string]$Label, [int]$TimeoutSeconds = 120)
    # Un changement de plateforme arrête Defender un moment : attente bornée de son retour en mode Normal
    # (120 s, comme l'exécuteur prévu au cahier des charges), avertissement en cas de dépassement.
    $waitStart = Get-Date
    $ready = $false
    while (((Get-Date) - $waitStart).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 5
        try {
            if ((Get-MpComputerStatus -ErrorAction Stop).AMRunningMode -eq 'Normal') { $ready = $true; break }
        } catch { Write-Host "Defender pas encore disponible : $($_.Exception.Message)" }
    }
    $lines.Add(('- Attente du retour de Defender ({0}) : {1} s, prêt : {2}' -f $Label, [math]::Round(((Get-Date) - $waitStart).TotalSeconds), $ready))
    if (-not $ready) { $lines.Add("- AVERTISSEMENT : Defender pas revenu en mode Normal après $TimeoutSeconds s ($Label), on continue") }
}

function Invoke-MpCmdRun {
    param([string[]]$Arguments)
    $mpcmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    $output = & $mpcmd @Arguments 2>&1
    $code = $LASTEXITCODE
    $lines.Add(('- `MpCmdRun {0}` : code {1}' -f ($Arguments -join ' '), $code))
    ($output | Out-String).Trim() | Out-File -FilePath (Join-Path $OutputDirectory ('mpcmdrun' + ($Arguments -join '') + '.txt')) -Encoding UTF8
}

$lines.Add("## R-06 : Defender ($Arch, variante $Variant), $env:PROCESSOR_ARCHITECTURE")
$lines.Add('')
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$lines.Add("Système : $($v.InstallationType) $($v.CurrentBuild).$($v.UBR)")
try {
    $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName })
    $lines.Add("Antivirus enregistrés (SecurityCenter2) : $($av -join ', ')")
} catch {
    $lines.Add('Antivirus enregistrés (SecurityCenter2) : indisponible (poste serveur ou classe absente)')
}
$lines.Add('')
$lines.Add('| Moment | AMRunningMode | Antivirus actif | Temps réel | Plateforme | Moteur | Définitions | Mise à jour des définitions |')
$lines.Add('|---|---|---|---|---|---|---|---|')
Get-DefenderState -Label 'Départ' | Out-Null

# Téléchargement et contrôle du fichier
$url = $DownloadUrl -f $Arch
$file = Join-Path $OutputDirectory "mpam-fe-$Arch.exe"
$trace = & curl.exe --silent --head --location --max-redirs 10 $url
$hosts = @(([uri]$url).Host) + @($trace | Where-Object { $_ -match '^(?i)location:\s*https?://([^/\s]+)' } | ForEach-Object { $Matches[1] }) | Select-Object -Unique
& curl.exe --fail --silent --show-error --location --retry 3 --output $file $url
if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE)" }
$info = (Get-Item $file).VersionInfo
$signature = Get-AuthenticodeSignature -FilePath $file
$fileVersion = $info.FileVersion

if ($PSCmdlet.ShouldProcess('Defender', 'Retour à la plateforme et aux définitions d''origine, puis mpam-fe.exe')) {
    Invoke-MpCmdRun -Arguments @('-ResetPlatform')
    if ($RemoveDefinitions) {
        Invoke-MpCmdRun -Arguments @('-RemoveDefinitions', '-All')
        Get-DefenderState -Label 'Après suppression des définitions' | Out-Null
    }
    Wait-DefenderNormal -Label 'retour à l''origine'
    Get-DefenderState -Label 'Après retour à l''origine' | Out-Null

    if ($PlatformUrl) {
        $platformUri = [uri]$PlatformUrl
        if ($platformUri.Scheme -ne 'https' -or $platformUri.Host -ne 'catalog.s.download.windowsupdate.com') { throw "Domaine non autorisé : $($platformUri.Host)" }
        $platformFile = Join-Path $OutputDirectory $platformUri.Segments[-1]
        & curl.exe --fail --silent --show-error --location --retry 3 --output $platformFile $PlatformUrl
        if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour la plateforme" }
        $platformSignature = Get-AuthenticodeSignature -FilePath $platformFile
        $expectedSha1 = [regex]::Match($platformUri.Segments[-1], '_([0-9a-f]{40})\.exe$').Groups[1].Value
        $actualSha1 = (Get-FileHash -Path $platformFile -Algorithm SHA1).Hash.ToLowerInvariant()
        $lines.Add(('- Plateforme : {0}, {1} Mo, FileVersion {2}, SHA-1 conforme au nom : {3}, Authenticode {4} ({5})' -f $platformUri.Segments[-1], [math]::Round((Get-Item $platformFile).Length / 1MB, 1), (Get-Item $platformFile).VersionInfo.FileVersion, ($expectedSha1 -eq $actualSha1), $platformSignature.Status, $platformSignature.SignerCertificate.Subject))
        $started = Get-Date
        $process = Start-Process -FilePath $platformFile -PassThru -WindowStyle Hidden
        if ($process.WaitForExit(900000)) {
            $lines.Add(('- `{0}` (sans argument) : code {1} (0x{1:X8}), {2} s' -f $platformUri.Segments[-1], $process.ExitCode, [math]::Round(((Get-Date) - $started).TotalSeconds)))
        } else {
            $process.Kill()
            $lines.Add('- Mise à jour de plateforme arrêtée après 15 min')
        }
        $pending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $lines.Add("- Redémarrage en attente (CBS) après la plateforme : $pending")
        Wait-DefenderNormal -Label 'plateforme'
        Get-DefenderState -Label 'Après mise à jour de plateforme' | Out-Null
        Remove-Item -Path $platformFile -Force
    }

    $attempts = New-Object System.Collections.Generic.List[string]
    $variants = @{ QuietThenPlain = @(@('-q'), @()); Quiet = @(, @('-q')); Plain = @(, @()) }
    foreach ($arguments in $variants[$Variant]) {
        $started = Get-Date
        if ($arguments.Count -gt 0) { $process = Start-Process -FilePath $file -ArgumentList $arguments -PassThru -WindowStyle Hidden }
        else { $process = Start-Process -FilePath $file -PassThru -WindowStyle Hidden }
        if (-not $process.WaitForExit(900000)) {
            $process.Kill()
            $attempts.Add(('- `mpam-fe.exe {0}` : arrêté après 15 min' -f ($arguments -join ' ')))
            continue
        }
        $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
        $attempts.Add(('- `mpam-fe.exe {0}` : code {1} (0x{1:X8}), {2} s' -f ($arguments -join ' '), $process.ExitCode, $seconds))
        $after = Get-DefenderState -Label ('Après mpam-fe.exe ' + ($arguments -join ' '))
        if ($after.Signatures -eq $fileVersion) { break }
    }
    $lines.Add('')
    foreach ($a in $attempts) { $lines.Add($a) }
}

$lines.Add('')
$lines.Add("Fichier : $([math]::Round((Get-Item $file).Length / 1MB, 1)) Mo, FileVersion $fileVersion, Authenticode $($signature.Status) ($($signature.SignerCertificate.Subject)), domaines : $($hosts -join ' → ')")
$summary = $lines -join "`n"
$summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
Write-Host $summary
Remove-Item -Path $file -Force
