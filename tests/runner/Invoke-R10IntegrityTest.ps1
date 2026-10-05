<#
.SYNOPSIS
    Essai R-10 sur un runner GitHub : signatures Authenticode des fichiers du dépôt et intégrité d'une source Office.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Scénario Signatures :
      - télécharge un échantillon de chaque type de fichier du dépôt (cumulatives .msu, SSU, enablement package,
        .NET, plateforme Defender, mpam-fe.exe, ODT) depuis des domaines autorisés ;
      - relève pour chacun : Status, SignatureType, signataire, émetteur, racine de la chaîne (X509Chain),
        horodatage, durée de Get-AuthenticodeSignature ;
      - refait la mesure hors ligne : cache d'URL vidé (certutil -urlcache * delete), règle de pare-feu bloquant
        les sorties de powershell.exe, contrôle lancé dans un processus PowerShell enfant.
    Scénario OfficeSource :
      - télécharge une source Current fr-fr, relève l'état Authenticode de chaque fichier de Office\Data ;
      - corrompt un octet au milieu du plus gros fichier .dat d'une copie de la source, bloque le CDN,
        lance l'installation hors ligne depuis la copie et relève le code retour et les journaux de l'ODT.

.EXAMPLE
    .\Invoke-R10IntegrityTest.ps1 -Scenario Signatures -OutputDirectory $env:RUNNER_TEMP\r10-out
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingBrokenHashAlgorithms', '', Justification = 'SHA-1 imposé par le nom de fichier du catalogue : comparaison d''empreinte, pas un contrôle de sécurité.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Signatures', 'OfficeSource')][string]$Scenario,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string[]]$Url = @(
        'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/10/ssu-19041.3562-x64_de23c91f483b2e609cec3e4a995639d13205f867.msu',
        'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9d8dc3d0-9cbf-4eb1-9411-722e3e6a19b3/public/Windows11.0-KB5121794-arm64_77a76caf2d362bb293a4d18058388f2717365abe.msu',
        'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/636c6186-6e83-481d-93a4-5131c454063f/public/windows11.0-kb5126052-arm64-ndp481_5678046ea7559df51f73ef43a2965b34717839f7.msu',
        'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2026/09/windows10.0-kb5129236-x64_4413bfb0ab8a665cd0244ed67ec361170bb12ecb.msu',
        'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/3750a920-b998-4242-8fed-32423df59284/public/windows11.0-kb5129195-arm64_e6b0a7f8c8cacdf87e8da1a01fe073934a0002b4.msu',
        'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/defu/2026/09/updateplatform.arm64fre_bd2a030040b4c71f8265ed53bfe2a639e071b96d.exe',
        'https://go.microsoft.com/fwlink/?LinkID=121721&arch=arm64'
    ),
    [string[]]$AllowedHost = @('catalog.sf.dl.delivery.mp.microsoft.com', 'catalog.s.download.windowsupdate.com', 'go.microsoft.com', 'definitionupdates.microsoft.com', 'download.microsoft.com', 'www.microsoft.com')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
. (Join-Path $PSScriptRoot 'OfficeRunner.Common.ps1')

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r10-work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-10 : scénario $Scenario ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')

function Get-SignatureDetail {
    param([string]$Path)
    $started = Get-Date
    $signature = Get-AuthenticodeSignature -FilePath $Path
    $seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $root = $null
    $chainStatus = $null
    if ($signature.SignerCertificate) {
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        [void]$chain.Build($signature.SignerCertificate)
        $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Subject
        $chainStatus = (@($chain.ChainStatus | ForEach-Object { $_.Status }) -join ',')
    }
    $signer = $null
    $issuer = $null
    $stamp = $null
    if ($signature.SignerCertificate) { $signer = $signature.SignerCertificate.Subject; $issuer = $signature.SignerCertificate.Issuer }
    if ($signature.TimeStamperCertificate) { $stamp = $signature.TimeStamperCertificate.Subject }
    [pscustomobject]@{
        Status      = [string]$signature.Status
        Type        = [string]$signature.SignatureType
        Signer      = $signer
        Issuer      = $issuer
        Root        = $root
        ChainStatus = $chainStatus
        TimeStamper = $stamp
        Seconds     = $seconds
    }
}

$firewallRule = 'OffPatch-R10-hors-ligne'
$hostsBackup = Join-Path $work 'hosts.bak'
try {
    switch ($Scenario) {
        'Signatures' {
            $files = New-Object System.Collections.Generic.List[string]
            foreach ($u in $Url) {
                $uri = [uri]$u
                if ($uri.Scheme -ne 'https' -or $AllowedHost -notcontains $uri.Host) { throw "Domaine non autorisé : $($uri.Host)" }
                $name = $uri.Segments[-1]
                if ($name -notmatch '\.(msu|exe|cab)$') { $name = 'mpam-fe-arm64.exe' }
                $file = Join-Path $work $name
                & curl.exe --fail --silent --show-error --location --retry 3 --output $file $u
                if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour $name" }
                $files.Add($file)
            }
            $files.Add((Join-Path $work 'odt.exe'))
            $page = (Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -UseBasicParsing).Content
            $odtUrl = [regex]::Matches($page, 'https://download\.microsoft\.com/[^"\\ ]+officedeploymenttool[^"\\ ]+\.exe') | ForEach-Object { $_.Value } | Select-Object -First 1
            & curl.exe --fail --silent --show-error --location --retry 3 --output (Join-Path $work 'odt.exe') $odtUrl

            $lines.Add('### En ligne')
            $lines.Add('')
            $lines.Add('| Fichier | Status | Type | Signataire | Émetteur | Racine | Chaîne | Horodatage | Durée (s) |')
            $lines.Add('|---|---|---|---|---|---|---|---|---|')
            foreach ($f in $files) {
                $d = Get-SignatureDetail -Path $f
                $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f (Split-Path -Leaf $f), $d.Status, $d.Type, $d.Signer, $d.Issuer, $d.Root, $d.ChainStatus, $d.TimeStamper, $d.Seconds))
            }

            # Hors ligne : cache d'URL vidé et sorties de powershell.exe bloquées ; contrôle dans un processus enfant.
            if ($PSCmdlet.ShouldProcess('pare-feu', 'Blocage des sorties de powershell.exe')) {
                & certutil.exe -urlcache * delete | Out-Null
                $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                New-NetFirewallRule -DisplayName $firewallRule -Direction Outbound -Action Block -Program $ps | Out-Null
                $probe = Join-Path $work 'probe.ps1'
                @'
param([string[]]$Files)
foreach ($f in $Files) {
    $t = Measure-Command { $s = Get-AuthenticodeSignature -FilePath $f }
    $web = 'injoignable'
    try { Invoke-WebRequest -Uri 'https://crl.microsoft.com' -UseBasicParsing -TimeoutSec 5 | Out-Null; $web = 'joignable' } catch { }
    '{0}|{1}|{2}|{3}' -f (Split-Path -Leaf $f), $s.Status, [math]::Round($t.TotalSeconds, 1), $web
}
'@ | Set-Content -Path $probe -Encoding UTF8
                $result = & $ps -NoProfile -ExecutionPolicy Bypass -File $probe -Files $files.ToArray()
                Remove-NetFirewallRule -DisplayName $firewallRule
                $lines.Add('')
                $lines.Add('### Hors ligne (cache vidé, sorties de powershell.exe bloquées)')
                $lines.Add('')
                $lines.Add('| Fichier | Status | Durée (s) | Réseau depuis le processus de contrôle |')
                $lines.Add('|---|---|---|---|')
                foreach ($r in $result) { $p = $r -split '\|'; $lines.Add(('| {0} | {1} | {2} | {3} |' -f $p[0], $p[1], $p[2], $p[3])) }
            }
        }
        'OfficeSource' {
            $setup = Initialize-OdtTool -WorkDirectory $work
            $source = Join-Path $work 'source'
            New-Item -ItemType Directory -Force -Path $source | Out-Null
            $download = Invoke-OdtSetup -Setup $setup -Mode 'download' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail') -ConfigPath (Join-Path $OutputDirectory '01-download.xml')
            $lines.Add(('- `setup.exe /download` : code {0}, {1} s' -f $download.ExitCode, $download.Seconds))
            $lines.Add('')
            $lines.Add('| Fichier de la source | Taille (Mo) | Status | Type | Signataire |')
            $lines.Add('|---|---|---|---|---|')
            foreach ($f in @(Get-ChildItem -Path (Join-Path $source 'Office\Data') -Recurse -File | Sort-Object FullName)) {
                $d = Get-SignatureDetail -Path $f.FullName
                $lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $f.FullName.Substring($source.Length), [math]::Round($f.Length / 1MB, 1), $d.Status, $d.Type, $d.Signer))
            }

            # Copie corrompue : un octet inversé au milieu du plus gros .dat
            $corrupt = Join-Path $work 'source-corrompue'
            Copy-Item -Path $source -Destination $corrupt -Recurse
            $target = Get-ChildItem -Path (Join-Path $corrupt 'Office\Data') -Recurse -File -Filter '*.dat' | Sort-Object Length -Descending | Select-Object -First 1
            $stream = [System.IO.File]::Open($target.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
            try {
                $stream.Position = [int64]($target.Length / 2)
                $byte = $stream.ReadByte()
                $stream.Position = [int64]($target.Length / 2)
                $stream.WriteByte([byte](255 - $byte))
            } finally { $stream.Dispose() }
            $lines.Add('')
            $lines.Add("- Octet inversé au milieu de $($target.Name) ($([math]::Round($target.Length / 1MB, 1)) Mo) dans la copie de la source")
            Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
            $lines.Add('- CDN Office bloqué')
            $install = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $corrupt -ProductId 'Home2024Retail' -NoCdnFallback -Display) -ConfigPath (Join-Path $OutputDirectory '02-install-corrompue.xml')
            $lines.Add(('- Installation depuis la source corrompue : code {0} (0x{0:X8}), {1} s' -f $install.ExitCode, $install.Seconds))
            $state = Get-ClickToRunState
            $lines.Add("- Office après coup : installé $($state.Installed), version $($state.Version), produits $($state.Products)")
        }
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    Get-NetFirewallRule -DisplayName $firewallRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Set-OfficeCdnBlock -Enabled $false -BackupPath $hostsBackup
    foreach ($folder in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))) {
        Get-ChildItem -Path $folder -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-3) } |
            Copy-Item -Destination $OutputDirectory -ErrorAction SilentlyContinue
    }
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
