<#
.SYNOPSIS
    Essai sur un runner GitHub (recentrage sur les mises à jour, R-08) : canal d'un Office installé lu dans le
    registre Click-to-Run, et conservation de la licence lors d'une mise à jour par /configure.

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système (installation d'Office) : ne jamais
    l'exécuter ailleurs. Aucune clé de produit n'est écrite dans ce script ni dans le workflow (CLAUDE.md).
    Scénario Channel : installe ProductId sur le canal Channel depuis le CDN, puis relève, sous
      HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration, CDNBaseUrl, UpdateChannel, UpdateChannelChanged,
      AudienceId, AudienceData, ProductReleaseIds, Platform et VersionToReport.
    Scénario License : installe ProPlus2024Volume dans une version ancienne depuis le CDN (sans PIDKEY : l'ODT
      installe la clé de licence en volume par défaut), relève l'état de licence avec les outils Office
      (cscript OSPP.VBS /dstatus : nom de licence, 5 derniers caractères de la clé), télécharge la source locale du
      canal, bloque le CDN, met à jour par setup.exe /configure depuis la source locale, puis relève à nouveau.

.EXAMPLE
    .\Invoke-OfficeUpdateScopeTest.ps1 -Scenario Channel -ProductId Home2024Retail -Channel Current -OutputDirectory $env:RUNNER_TEMP\scope-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('Channel', 'License')][string]$Scenario,
    [string]$ProductId = 'ProPlus2024Volume',
    [string]$Channel = 'PerpetualVL2024',
    [string]$OlderVersion = '16.0.17932.20976',
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
. (Join-Path $PSScriptRoot 'OfficeRunner.Common.ps1')

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'scope-work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$hostsBackup = Join-Path $work 'hosts.bak'
$lines = New-Object System.Collections.Generic.List[string]

function Get-C2RChannelValue {
    $c = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $c) { return 'Click-to-Run absent' }
    $names = 'CDNBaseUrl', 'UpdateChannel', 'UpdateChannelChanged', 'AudienceId', 'AudienceData', 'ProductReleaseIds', 'Platform', 'VersionToReport', 'UpdateUrl'
    @(foreach ($n in $names) { if ($c.PSObject.Properties[$n]) { "- ``$n`` : $($c.$n)" } else { "- ``$n`` : (absent)" } })
}

function Get-OfficeLicense {
    $ospp = Join-Path $env:ProgramFiles 'Microsoft Office\Office16\OSPP.VBS'
    if (-not (Test-Path $ospp)) { return @("OSPP.VBS absent ($ospp)") }
    $out = & cscript.exe //Nologo $ospp /dstatus 2>&1
    @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^(LICENSE NAME|LICENSE DESCRIPTION|LICENSE STATUS|Last 5 characters of installed product key|ERROR CODE|PRODUCT ID|SKU ID)' })
}

try {
    $setup = Initialize-OdtTool -WorkDirectory $work
    switch ($Scenario) {
        'Channel' {
            $lines.Add("## Canal d'un Office installé : $ProductId, canal $Channel ($env:PROCESSOR_ARCHITECTURE)")
            $lines.Add('')
            if ($PSCmdlet.ShouldProcess($ProductId, 'Installation depuis le CDN')) {
                $r = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml (Get-OdtConfigurationXml -Channel $Channel -ProductId $ProductId -Display) -ConfigPath (Join-Path $OutputDirectory 'install.xml') -TimeoutMinutes 60
                $lines.Add(('- `setup.exe /configure` (CDN) : code {0}, {1} s, délai dépassé : {2}' -f $r.ExitCode, $r.Seconds, $r.TimedOut))
            }
            $lines.Add('')
            $lines.Add('Registre Click-to-Run après installation :')
            $lines.Add('')
            foreach ($l in Get-C2RChannelValue) { $lines.Add($l) }
        }
        'License' {
            $lines.Add("## Licence conservée par une mise à jour /configure : $ProductId, canal $Channel ($env:PROCESSOR_ARCHITECTURE)")
            $lines.Add('')
            if ($PSCmdlet.ShouldProcess($ProductId, 'Installation ancienne, puis mise à jour depuis la source locale')) {
                $r = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml (Get-OdtConfigurationXml -Channel $Channel -ProductId $ProductId -Version $OlderVersion -Display) -ConfigPath (Join-Path $OutputDirectory '01-install-ancienne.xml') -TimeoutMinutes 60
                $lines.Add(('- Installation de {0} depuis le CDN : code {1}, {2} s' -f $OlderVersion, $r.ExitCode, $r.Seconds))
                $before = Get-ClickToRunState
                $lines.Add("- Version avant : $($before.Version)")
                $lines.Add('')
                $lines.Add('Licence avant (OSPP.VBS /dstatus) :')
                $lines.Add('')
                foreach ($l in Get-OfficeLicense) { $lines.Add("- $l") }
                $lines.Add('')

                $source = Join-Path $work 'source'
                New-Item -ItemType Directory -Force -Path $source | Out-Null
                $d = Invoke-OdtSetup -Setup $setup -Mode 'download' -Xml (Get-OdtConfigurationXml -SourcePath $source -Channel $Channel -ProductId $ProductId) -ConfigPath (Join-Path $OutputDirectory '02-download.xml') -TimeoutMinutes 60
                $lines.Add(('- Source locale téléchargée : code {0}, {1} s' -f $d.ExitCode, $d.Seconds))
                Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
                $u = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -Channel $Channel -ProductId $ProductId -NoCdnFallback -Display) -ConfigPath (Join-Path $OutputDirectory '03-mise-a-jour.xml') -TimeoutMinutes 30
                $lines.Add(('- Mise à jour par /configure depuis la source locale, CDN bloqué : code {0}, {1} s, délai dépassé : {2}' -f $u.ExitCode, $u.Seconds, $u.TimedOut))
                $after = Get-ClickToRunState
                $lines.Add("- Version après : $($after.Version)")
                $lines.Add('')
                $lines.Add('Licence après (OSPP.VBS /dstatus) :')
                $lines.Add('')
                foreach ($l in Get-OfficeLicense) { $lines.Add("- $l") }
            }
        }
    }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    Set-OfficeCdnBlock -Enabled $false -BackupPath $hostsBackup
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
