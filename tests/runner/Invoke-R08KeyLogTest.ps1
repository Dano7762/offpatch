<#
.SYNOPSIS
    Essai R-08 sur un runner GitHub : une clé de produit passée à l'ODT apparaît-elle dans ses journaux ?

.DESCRIPTION
    Script réservé aux runners GitHub hébergés (jetables). Il modifie le système : ne jamais l'exécuter ailleurs.
    Installe Office LTSC Professionnel Plus 2024 (ProPlus2024Volume, canal PerpetualVL2024, depuis le CDN) avec une
    FAUSSE clé de forme valide, les journaux de l'ODT dirigés vers un dossier de session par <Logging Path> (ce
    qu'OffPatch copiera dans la session et sur le support). Puis recherche, sans tenir compte de la casse, de la
    clé complète avec tirets, de la clé sans tirets et de ses 5 derniers caractères seuls, en UTF-8 et en UTF-16,
    dans tous les fichiers créés ou modifiés pendant l'essai sous : le dossier de journaux de l'ODT, TEMP de
    l'utilisateur, Windows\Temp, ProgramData\Microsoft\Office et ClickToRun, Common Files\microsoft shared\
    ClickToRun, LocalAppData\Microsoft\Office. Le XML de configuration de l'essai est exclu.
    Chaque occurrence est classée : fichier du dossier de journaux de l'ODT (copié par OffPatch) ou ailleurs.
    Les journaux de l'ODT sont joints à l'artefact (la clé est inventée et ne peut rien activer).

.EXAMPLE
    .\Invoke-R08KeyLogTest.ps1 -OutputDirectory $env:RUNNER_TEMP\r08-key-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    # Fausse clé de forme réaliste : alphabet des clés de produit (BCDFGHJKMPQRTVWXY2346789), cinq groupes de cinq.
    [ValidatePattern('^[BCDFGHJKMPQRTVWXY2346789]{5}(-[BCDFGHJKMPQRTVWXY2346789]{5}){4}$')][string]$FakeKey = 'BCDFG-HJKMP-QRTVW-XY234-6789B'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script modifie le système : il ne s''exécute que sur un runner GitHub hébergé.'
}
. (Join-Path $PSScriptRoot 'OfficeRunner.Common.ps1')

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$work = Join-Path $env:RUNNER_TEMP 'r08-key-work'
$configFolder = Join-Path $env:RUNNER_TEMP 'r08-key-config'
$odtLogs = Join-Path $env:RUNNER_TEMP 'r08-key-session\odt'
foreach ($f in $work, $configFolder, $odtLogs) { New-Item -ItemType Directory -Force -Path $f | Out-Null }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## R-08 : clé de produit dans les journaux de l'ODT ($env:PROCESSOR_ARCHITECTURE)")
$lines.Add('')

$started = (Get-Date).AddMinutes(-1)
try {
    $setup = Initialize-OdtTool -WorkDirectory $work
    $xml = Get-OdtConfigurationXml -Channel 'PerpetualVL2024' -ProductId 'ProPlus2024Volume' -ProductKey $FakeKey -Display -LogPath $odtLogs
    if ($PSCmdlet.ShouldProcess('ProPlus2024Volume', 'setup.exe /configure avec une fausse clé')) {
        $install = Invoke-OdtSetup -Setup $setup -Mode 'configure' -Xml $xml -ConfigPath (Join-Path $configFolder 'install.xml') -TimeoutMinutes 60
        $lines.Add(('- `setup.exe /configure` : code {0}, {1} s, délai dépassé : {2}' -f $install.ExitCode, $install.Seconds, $install.TimedOut))
        $state = Get-ClickToRunState
        $lines.Add("- Office après coup : installé $($state.Installed), version $($state.Version), produits $($state.Products)")
    }

    $forms = @(
        @('clé complète avec tirets', $FakeKey),
        @('clé sans tirets', ($FakeKey -replace '-', '')),
        @('5 derniers caractères', $FakeKey.Substring($FakeKey.Length - 5))
    )
    $roots = @($odtLogs, $env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:ProgramData 'Microsoft\Office'), (Join-Path $env:ProgramData 'Microsoft\ClickToRun'),
        (Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Office')) | Where-Object { Test-Path $_ }
    $files = @(foreach ($r in $roots) {
            Get-ChildItem -Path $r -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $started -and $_.FullName -notlike "$configFolder*" -and $_.FullName -notlike "$work*" -and $_.Length -lt 50MB }
        }) | Sort-Object FullName -Unique
    $odtFiles = @($files | Where-Object { $_.FullName -like "$odtLogs*" })
    $lines.Add("- Dossier de journaux de l'ODT (``<Logging Path>``, copié par OffPatch) : $($odtFiles.Count) fichier(s) : $(@($odtFiles | ForEach-Object { $_.Name }) -join ', ')")
    $lines.Add("- Fichiers examinés en tout (créés ou modifiés pendant l'essai) : $($files.Count)")
    $lines.Add('')
    $lines.Add('| Fichier | Copié par OffPatch | Forme trouvée | Encodage | Occurrences |')
    $lines.Add('|---|---|---|---|---|')
    $hits = 0
    $copiedHits = 0
    foreach ($file in $files) {
        try { $bytes = [IO.File]::ReadAllBytes($file.FullName) } catch { continue }
        $copied = $file.FullName -like "$odtLogs*"
        foreach ($encoding in @(@('UTF-8', [Text.Encoding]::UTF8), @('UTF-16', [Text.Encoding]::Unicode))) {
            $text = $encoding[1].GetString($bytes)
            foreach ($form in $forms) {
                $count = [regex]::Matches($text, [regex]::Escape($form[1]), [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
                if ($count -gt 0) {
                    $lines.Add("| $($file.FullName) | $copied | $($form[0]) | $($encoding[0]) | $count |")
                    $hits++
                    if ($copied) { $copiedHits++ }
                }
            }
        }
    }
    if ($hits -eq 0) { $lines.Add('| (aucune occurrence) | | | | |') }
    $lines.Add('')
    $lines.Add("- Lignes d'occurrence : $hits, dont $copiedHits dans les fichiers copiés par OffPatch")
    $files | Select-Object FullName, Length, LastWriteTime | Export-Csv -Path (Join-Path $OutputDirectory 'fichiers-examines.csv') -NoTypeInformation -Encoding UTF8
    # Pièces jointes (fausse clé, sans valeur) : XML utilisé, journaux du dossier <Logging Path>, journaux de l'ODT
    # écrits dans TEMP (nom <machine>-AAAAMMJJ-HHMM.log).
    $odtCopy = Join-Path $OutputDirectory 'journaux-odt'
    New-Item -ItemType Directory -Force -Path $odtCopy | Out-Null
    Copy-Item -Path (Join-Path $configFolder 'install.xml') -Destination $odtCopy -ErrorAction SilentlyContinue
    foreach ($f in $odtFiles) { Copy-Item -Path $f.FullName -Destination $odtCopy -ErrorAction SilentlyContinue }
    $tempOdt = @($files | Where-Object { $_.DirectoryName -eq (Get-Item $env:TEMP).FullName -and $_.Name -match '^[^\\]+-\d{8}-\d{4}\.log$' })
    $lines.Add("- Journaux de l'ODT dans TEMP : $(@($tempOdt | ForEach-Object { $_.Name }) -join ', ')")
    foreach ($f in $tempOdt) { Copy-Item -Path $f.FullName -Destination $odtCopy -ErrorAction SilentlyContinue }
} catch {
    $lines.Add("- ERREUR : $($_.Exception.Message)")
    throw
} finally {
    $summary = $lines -join "`n"
    $summary | Set-Content -Path (Join-Path $OutputDirectory 'resume.md') -Encoding UTF8
    if ($env:GITHUB_STEP_SUMMARY) { $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8 }
    Write-Host $summary
}
