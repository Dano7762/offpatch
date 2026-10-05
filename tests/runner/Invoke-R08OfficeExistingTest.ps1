<#
.SYNOPSIS
    Essai R-08 sur un runner GitHub : Office déjà présent (retrait, mise à jour hors ligne).

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Un scénario par exécution, sur un runner neuf :
      RemoveAdd         : O365HomePremRetail fr-fr + en-us installé depuis le CDN (Office « constructeur »), puis,
                          CDN bloqué, <Remove All="TRUE" /> et <Add> Home2024Retail depuis la source locale dans le
                          même XML ; si le produit d'origine reste en place, retrait puis installation en deux passes.
      UpdateConfigure   : Home2024Retail installé en version ancienne depuis la source locale, puis, CDN bloqué,
                          setup.exe /configure relancé sur la source qui contient la version récente.
      UpdateC2RClient   : même départ, puis chemin de mise à jour local temporaire (UpdateUrl) et
                          OfficeC2RClient.exe /update ; UpdateUrl restauré ensuite.
      HomePremConfigure : O365HomePremRetail en version ancienne depuis le CDN, puis, CDN bloqué, setup.exe /configure
                          sur la source Current locale (téléchargée pour Home2024Retail).
      HomePremC2RClient : même départ, puis UpdateUrl local et OfficeC2RClient.exe /update.
      MultiLangPlain    : Home2024Retail fr-fr + en-us en version ancienne depuis le CDN, puis, CDN bloqué, /configure
                          depuis une source fr-fr seule avec <Language ID="fr-fr" />.
      MultiLangMatch    : même départ, puis /configure depuis la source fr-fr seule avec <Language ID="MatchInstalled" />.
      SourceSize        : taille d'une source Current fr-fr seule, puis fr-fr + en-us (téléchargements seulement).
    Les applications du Store (application Microsoft 365, Office Hub) sont relevées avant et après, jamais modifiées.

.EXAMPLE
    .\Invoke-R08OfficeExistingTest.ps1 -Scenario RemoveAdd -OlderVersion 16.0.20430.20092 -OutputDirectory $env:RUNNER_TEMP\r08-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('RemoveAdd', 'UpdateConfigure', 'UpdateC2RClient', 'HomePremConfigure', 'HomePremC2RClient', 'MultiLangPlain', 'MultiLangMatch', 'SourceSize')][string]$Scenario,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$OlderVersion = '16.0.20430.20092',
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
. (Join-Path $PSScriptRoot 'OfficeRunner.Common.ps1')

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r08-work'
$source = Join-Path $work 'source'
$hostsBackup = Join-Path $work 'hosts.bak'
New-Item -ItemType Directory -Force -Path $source | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-08 : scénario $Scenario ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')
$step = 0

function Invoke-Step {
    param([string]$Label, [string]$Mode, [string]$Xml)
    $script:step++
    $result = Invoke-OdtSetup -Setup $setup -Mode $Mode -Xml $Xml -ConfigPath (Join-Path $OutputDirectory ('{0:00}-{1}.xml' -f $script:step, $Label))
    $lines.Add(('- `setup.exe /{0}` ({1}) : code {2}, {3} s' -f $Mode, $Label, $result.ExitCode, $result.Seconds))
    $result
}

function Add-State {
    param([string]$Label)
    $s = Get-ClickToRunState
    $lines.Add(('- État après {0} : installé {1}, version {2}, produits {3}, langues (registre) [{4}], UpdateUrl {5}' -f $Label, $s.Installed, $s.Version, $s.Products, $s.Languages, $s.UpdateUrl))
    $word = Join-Path $env:ProgramFiles 'Microsoft Office
oot\Office16\WINWORD.EXE'
    $client = Join-Path ${env:CommonProgramFiles} 'microsoft shared\ClickToRun\OfficeClickToRun.exe'
    $wordVersion = $null
    $clientVersion = $null
    if (Test-Path $word) { $wordVersion = (Get-Item $word).VersionInfo.FileVersion }
    if (Test-Path $client) { $clientVersion = (Get-Item $client).VersionInfo.FileVersion }
    $lines.Add(('  Fichiers : WINWORD.EXE {0}, OfficeClickToRun.exe {1}' -f $wordVersion, $clientVersion))
    $script:step++
    & reg.exe export 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun' (Join-Path $OutputDirectory ('{0:00}-registre-clicktorun.reg' -f $script:step)) /y | Out-Null
    $s
}

function Invoke-C2RClientUpdate {
    param([string]$ExpectedVersion)
    $key = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $previous = (Get-ClickToRunState).UpdateUrl
    Set-ItemProperty -Path $key -Name 'UpdateUrl' -Value $source
    $lines.Add("- UpdateUrl temporaire : $source (valeur précédente : $previous)")
    $client = Join-Path ${env:CommonProgramFiles} 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
    $started = Get-Date
    $process = Start-Process -FilePath $client -ArgumentList '/update', 'user', 'displaylevel=false', 'forceappshutdown=true', 'updatepromptuser=false' -Wait -PassThru
    $lines.Add(('- `OfficeC2RClient.exe /update user displaylevel=false forceappshutdown=true updatepromptuser=false` : code {0}, {1} s' -f $process.ExitCode, [math]::Round(((Get-Date) - $started).TotalSeconds)))
    # La mise à jour se poursuit en arrière-plan : on attend la nouvelle version (20 min au plus).
    $deadline = (Get-Date).AddMinutes(20)
    while ((Get-Date) -lt $deadline -and (Get-ClickToRunState).Version -ne $ExpectedVersion) { Start-Sleep -Seconds 20 }
    $lines.Add(('- Attente de la version {0} : {1} s' -f $ExpectedVersion, [math]::Round(((Get-Date) - $started).TotalSeconds)))
    if ($null -eq $previous) { Remove-ItemProperty -Path $key -Name 'UpdateUrl' -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -Path $key -Name 'UpdateUrl' -Value $previous }
    $lines.Add("- UpdateUrl restauré : $((Get-ClickToRunState).UpdateUrl)")
}

try {
    $lines.Add("- Applications Office du Store au départ : $(Get-StoreOfficeApp)")
    $setup = Initialize-OdtTool -WorkDirectory $work
    $lines.Add("- ODT : setup.exe $((Get-Item $setup).VersionInfo.FileVersion)")

    # Source locale Current fr-fr (Home2024Retail) : version ancienne si utile, puis dernière version
    if ($Scenario -like 'Update*') {
        Invoke-Step -Label 'source-ancienne' -Mode 'download' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -Version $OlderVersion) | Out-Null
    }
    Invoke-Step -Label 'source-derniere' -Mode 'download' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail') | Out-Null
    $tmp = Join-Path $work 'v64'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    & expand.exe '-F:v64.hash' (Join-Path $source 'Office\Data\v64.cab') $tmp | Out-Null
    $latest = (Get-Content -Path (Join-Path $tmp 'v64.hash'))[1].Trim()
    $lines.Add("- Source : dernière version $latest ; dossiers $((Get-ChildItem (Join-Path $source 'Office\Data') -Directory | ForEach-Object { $_.Name }) -join ', ')")

    switch ($Scenario) {
        'RemoveAdd' {
            Invoke-Step -Label 'homeprem-cdn' -Mode 'configure' -Xml (Get-OdtConfigurationXml -ProductId 'O365HomePremRetail' -Language 'fr-fr', 'en-us' -Display) | Out-Null
            Add-State -Label 'installation d''O365HomePremRetail fr-fr + en-us (CDN)' | Out-Null
            Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
            $lines.Add('- CDN Office bloqué')
            $combined = Invoke-Step -Label 'remove-et-add' -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -NoCdnFallback -RemoveAll -Display)
            $state = Add-State -Label '<Remove All="TRUE" /> + <Add> Home2024Retail dans le même XML'
            $ok = ($combined.ExitCode -eq 0 -and $state.Products -eq 'Home2024Retail')
            $lines.Add("- Remove + Add dans le même XML : $(if ($ok) { 'réussi' } else { 'non concluant, passage en deux temps' })")
            if (-not $ok) {
                Invoke-Step -Label 'remove-seul' -Mode 'configure' -Xml (Get-OdtConfigurationXml -RemoveAll -Display) | Out-Null
                Add-State -Label 'retrait seul' | Out-Null
                Invoke-Step -Label 'add-seul' -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -NoCdnFallback -Display) | Out-Null
                Add-State -Label 'installation seule' | Out-Null
            }
        }
        { $_ -in 'UpdateConfigure', 'UpdateC2RClient' } {
            Invoke-Step -Label 'install-ancienne' -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -Version $OlderVersion -NoCdnFallback -Display) | Out-Null
            Add-State -Label "installation de Home2024Retail $OlderVersion (source locale)" | Out-Null
            Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
            $lines.Add('- CDN Office bloqué')
            if ($Scenario -eq 'UpdateConfigure') {
                Invoke-Step -Label 'configure-mise-a-jour' -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -NoCdnFallback -Display) | Out-Null
            } else {
                Invoke-C2RClientUpdate -ExpectedVersion $latest
            }
            Add-State -Label 'mise à jour hors ligne' | Out-Null
        }
        { $_ -in 'MultiLangPlain', 'MultiLangMatch' } {
            Invoke-Step -Label 'install-bilingue-cdn' -Mode 'configure' -Xml (Get-OdtConfigurationXml -ProductId 'Home2024Retail' -Language 'fr-fr', 'en-us' -Version $OlderVersion -Display) | Out-Null
            Add-State -Label "installation de Home2024Retail $OlderVersion fr-fr + en-us (CDN)" | Out-Null
            Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
            $lines.Add('- CDN Office bloqué ; source locale fr-fr seule')
            $language = 'fr-fr'
            if ($Scenario -eq 'MultiLangMatch') { $language = 'MatchInstalled' }
            $result = Invoke-Step -Label "configure-$language" -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'Home2024Retail' -Language $language -NoCdnFallback -Display)
            $lines.Add(('- Code retour de la mise à jour avec Language ID="{0}" : {1} (0x{1:X8})' -f $language, $result.ExitCode))
            Add-State -Label "mise à jour depuis une source fr-fr seule (Language $language)" | Out-Null
        }
        'SourceSize' {
            $sizeOf = { param($path) $total = [int64]0; foreach ($f in @(Get-ChildItem -Path $path -Recurse -File)) { $total += $f.Length }; [math]::Round($total / 1MB, 1) }
            $lines.Add("- Taille de la source Current fr-fr seule : $(& $sizeOf $source) Mo")
            $source2 = Join-Path $work 'source-fr-en'
            New-Item -ItemType Directory -Force -Path $source2 | Out-Null
            Invoke-Step -Label 'source-fr-en' -Mode 'download' -Xml (Get-OdtConfigurationXml -SourcePath $source2 -ProductId 'Home2024Retail' -Language 'fr-fr', 'en-us') | Out-Null
            $lines.Add("- Taille de la source Current fr-fr + en-us : $(& $sizeOf $source2) Mo")
            foreach ($dir in @(Get-ChildItem -Path (Join-Path $source2 'Office\Data') -Recurse -Directory)) {
                $files = @(Get-ChildItem -Path $dir.FullName -File | Sort-Object Length -Descending | Select-Object -First 3 | ForEach-Object { '{0} ({1} Mo)' -f $_.Name, [math]::Round($_.Length / 1MB, 1) })
                $lines.Add(('    {0} : plus gros fichiers {1}' -f $dir.Name, ($files -join ', ')))
            }
        }
        { $_ -in 'HomePremConfigure', 'HomePremC2RClient' } {
            Invoke-Step -Label 'homeprem-cdn-ancienne' -Mode 'configure' -Xml (Get-OdtConfigurationXml -ProductId 'O365HomePremRetail' -Version $OlderVersion -Display) | Out-Null
            Add-State -Label "installation d'O365HomePremRetail $OlderVersion (CDN)" | Out-Null
            Set-OfficeCdnBlock -Enabled $true -BackupPath $hostsBackup
            $lines.Add('- CDN Office bloqué')
            if ($Scenario -eq 'HomePremConfigure') {
                Invoke-Step -Label 'configure-homeprem' -Mode 'configure' -Xml (Get-OdtConfigurationXml -SourcePath $source -ProductId 'O365HomePremRetail' -NoCdnFallback -Display) | Out-Null
            } else {
                Invoke-C2RClientUpdate -ExpectedVersion $latest
            }
            Add-State -Label 'mise à jour hors ligne depuis la source Current' | Out-Null
        }
    }
    $lines.Add("- Applications Office du Store à la fin : $(Get-StoreOfficeApp)")
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
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
