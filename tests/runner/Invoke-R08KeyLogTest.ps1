<#
.SYNOPSIS
    Essai R-08 sur un runner GitHub : une clé de produit passée à l'ODT apparaît-elle dans ses journaux ?

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Installe Office LTSC Professionnel Plus 2024 (ProPlus2024Volume, canal PerpetualVL2024, depuis le CDN) avec une
    FAUSSE clé de forme valide (cinq groupes de cinq caractères), puis cherche la clé, avec et sans tirets, en UTF-8
    et en UTF-16, dans tous les fichiers produits ou modifiés depuis le début de l'essai sous : TEMP de l'utilisateur,
    Windows\Temp, ProgramData\Microsoft\Office, ProgramData\Microsoft\ClickToRun, Common Files\microsoft shared\
    ClickToRun, LocalAppData\Microsoft\Office. Le XML de configuration de l'essai est exclu de la recherche.
    Le résumé donne les fichiers où la clé apparaît (chemin, taille, forme trouvée), jamais leur contenu.
    Aucune clé réelle : la clé est inventée et ne peut rien activer.

.EXAMPLE
    .\Invoke-R08KeyLogTest.ps1 -OutputDirectory $env:RUNNER_TEMP\r08-key-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidatePattern('^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$')][string]$FakeKey = 'FAKE0-KEY00-OFFPA-TCH00-TEST1'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
. (Join-Path $PSScriptRoot 'OfficeRunner.Common.ps1')

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r08-key-work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$configFolder = Join-Path $env:RUNNER_TEMP 'r08-key-config'
New-Item -ItemType Directory -Force -Path $configFolder | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-08 : clé de produit dans les journaux de l'ODT ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')

$started = (Get-Date).AddMinutes(-1)
try {
    $setup = Initialize-OdtTool -WorkDirectory $work
    $xml = Get-OdtConfigurationXml -Channel 'PerpetualVL2024' -ProductId 'ProPlus2024Volume' -ProductKey $FakeKey -Display
    if ($PSCmdlet.ShouldProcess('ProPlus2024Volume', 'setup.exe /configure avec une fausse clé')) {
        $install = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml $xml -ConfigPath (Join-Path $configFolder 'install.xml') -TimeoutMinutes 60
        $lines.Add(('- `setup.exe /configure` : code {0}, {1} s, délai dépassé : {2}' -f $install.ExitCode, $install.Seconds, $install.TimedOut))
        $state = Get-ClickToRunState
        $lines.Add("- Office après coup : installé $($state.Installed), version $($state.Version), produits $($state.Products)")
    }

    # Recherche de la clé : avec et sans tirets, en UTF-8 (ou ASCII) et en UTF-16.
    $forms = @($FakeKey, ($FakeKey -replace '-', ''))
    $patterns = foreach ($f in $forms) {
        [pscustomobject]@{ Label = "texte : $($f.Length) caractères"; Bytes = [Text.Encoding]::UTF8.GetBytes($f) }
        [pscustomobject]@{ Label = "UTF-16 : $($f.Length) caractères"; Bytes = [Text.Encoding]::Unicode.GetBytes($f) }
    }
    $roots = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:ProgramData 'Microsoft\Office'), (Join-Path $env:ProgramData 'Microsoft\ClickToRun'),
        (Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Office')) | Where-Object { Test-Path $_ }
    $files = @(foreach ($r in $roots) {
            Get-ChildItem -Path $r -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $started -and $_.FullName -notlike "$configFolder*" -and $_.FullName -notlike "$work*" -and $_.Length -lt 50MB }
        })
    $lines.Add("- Fichiers examinés (créés ou modifiés pendant l'essai) : $($files.Count), dans : $($roots -join ' ; ')")
    $lines.Add('')
    $lines.Add('| Fichier | Taille (octets) | Forme trouvée |')
    $lines.Add('|---|---|---|')
    $hits = 0
    foreach ($file in $files) {
        try { $content = [IO.File]::ReadAllBytes($file.FullName) } catch { continue }
        $text = [BitConverter]::ToString($content)
        foreach ($p in $patterns) {
            $needle = [BitConverter]::ToString($p.Bytes)
            if ($text.Contains($needle)) {
                $lines.Add("| $($file.FullName) | $($file.Length) | $($p.Label) |")
                $hits++
            }
        }
    }
    if ($hits -eq 0) { $lines.Add('| (aucun) | | |') }
    $lines.Add('')
    $lines.Add("- Occurrences de la clé : $hits")
    $files | Select-Object FullName, Length, LastWriteTime | Export-Csv -Path (Join-Path $OutputDirectory 'fichiers-examines.csv') -NoTypeInformation -Encoding UTF8
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
