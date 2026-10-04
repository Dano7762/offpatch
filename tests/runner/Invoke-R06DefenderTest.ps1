<#
.SYNOPSIS
    Essai R-06 sur un runner GitHub : application de mpam-fe.exe sur une plateforme Defender d'origine.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
      1. état de Defender (Get-MpComputerStatus) et antivirus enregistrés (SecurityCenter2, poste client) ;
      2. téléchargement de mpam-fe.exe par le lien officiel, version du fichier et signature ;
      3. simulation d'une installation récente : MpCmdRun -ResetPlatform (plateforme de l'image), et -RemoveDefinitions -All si demandé ;
      4. application de mpam-fe.exe selon -Variant : avec -q, sans argument, ou -q puis sans argument si -q échoue ; code retour et durée ;
      5. état final : la version des définitions doit être celle du fichier.
    Les résultats sont relevés, pas jugés : le script n'échoue que sur une erreur imprévue.

.EXAMPLE
    .\Invoke-R06DefenderTest.ps1 -Arch x64 -OutputDirectory $env:RUNNER_TEMP\r06-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('x64', 'arm64')][string]$Arch = 'x64',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$DownloadUrl = 'https://go.microsoft.com/fwlink/?LinkID=121721&arch={0}',
    [ValidateSet('QuietThenPlain', 'Quiet', 'Plain')][string]$Variant = 'QuietThenPlain',
    [switch]$RemoveDefinitions
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
            Platform          = $s.AMProductVersion
            Engine            = $s.AMEngineVersion
            Signatures        = $s.AntivirusSignatureVersion
            SignaturesUpdated = $s.AntivirusSignatureLastUpdated
        }
    } catch {
        $state = [pscustomobject]@{ Label = $Label; AMRunningMode = "Erreur : $($_.Exception.Message)"; AMServiceEnabled = $null; AntivirusEnabled = $null; Platform = $null; Engine = $null; Signatures = $null; SignaturesUpdated = $null }
    }
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $state.Label, $state.AMRunningMode, $state.AntivirusEnabled, $state.Platform, $state.Engine, $state.Signatures, $state.SignaturesUpdated))
    $state
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
$lines.Add('| Moment | AMRunningMode | Antivirus actif | Plateforme | Moteur | Définitions | Mise à jour des définitions |')
$lines.Add('|---|---|---|---|---|---|---|')
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
    if ($RemoveDefinitions) { Invoke-MpCmdRun -Arguments @('-RemoveDefinitions', '-All') }
    Get-DefenderState -Label 'Après retour à l''origine' | Out-Null

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
