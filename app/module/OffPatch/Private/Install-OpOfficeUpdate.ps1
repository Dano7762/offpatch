function Install-OpOfficeUpdate {
    <#
    .SYNOPSIS
        Met à jour l'Office Click-to-Run installé depuis la source locale de son canal (setup.exe /configure).

    .DESCRIPTION
        Cahier des charges 8.5 (R-08, R-10). Mise à jour seulement : aucun produit installé ni retiré, aucune clé.
          1. Office relu dans le registre Click-to-Run (Get-OpOfficeInstallation) : absent, Office 32 bits (la source
             du dépôt est en 64 bits), canal différent de celui de la source (installedChannelIds) ou langue installée
             absente de la source : NotApplicable, l'ODT n'est pas lancé.
          2. SHA-256 de tous les fichiers de la source revérifié : au moindre écart, Error avec la liste, l'ODT n'est
             pas lancé (hors ligne, l'ODT face à une source corrompue attend le réseau, R-10).
          3. XML tiré de config\office\update.xml.template (6.3) : chemin absolu de la source, canal, un
             <Product ID> par produit installé avec ses langues ; écrit dans ProgramData\OffPatch\temp.
          4. Invoke-OpOfficeSetup /configure, délai odtTimeoutMinutes : il copie les journaux de l'ODT du TEMP dans
             LogDirectory et supprime le XML sur tous les chemins de sortie.
          5. Jugement : délai dépassé, Error « délai dépassé » ; code autre que 0, Error avec le code ; code 0, Office
             relu : UpToDate si la version de fichier atteint celle de la source, Error sinon.
        Renvoie Id, Category, State, Reason, ExitCode, Before, Installed, Available et OdtLogs.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][string]$LogDirectory,
        [string]$Root,
        [pscustomobject]$Configuration
    )

    if ($Item.category -ne 'office-source') { throw "Install-OpOfficeUpdate : catégorie $($Item.category) non prise en charge." }
    if (-not $Root) { $Root = Get-OpRoot }
    if (-not $Configuration) { $Configuration = Get-OpConfiguration -Root $Root }
    $depot = Get-OpPath -Name Depot -Root $Root
    $available = [string]$Item.version

    function ConvertTo-StepResult([string]$State, [string]$Reason, $ExitCode, $Before, $Installed, [string[]]$OdtLogs) {
        if ($State -eq 'Error') { Write-OpLog "$($Item.id) : $Reason" -Level ERROR } else { Write-OpLog "$($Item.id) : $Reason" }
        [pscustomobject]@{ Id = $Item.id; Category = $Item.category; State = $State; Reason = $Reason; ExitCode = $ExitCode; Before = $Before; Installed = $Installed; Available = $available; OdtLogs = @($OdtLogs) }
    }
    function ConvertTo-XmlText([string]$Text) { [Security.SecurityElement]::Escape($Text) }

    $office = Get-OpOfficeInstallation
    if (-not $office) { return (ConvertTo-StepResult 'NotApplicable' 'Aucun Office Click-to-Run.' $null $null $null @()) }
    $before = $office.Version
    if ([string]$office.Platform -eq 'x86') { return (ConvertTo-StepResult 'NotApplicable' 'Office 32 bits : la source du dépôt est en 64 bits.' $null $before $before @()) }
    $source = @($Configuration.OfficeSources.sources | Where-Object { $_.folder -eq $Item.folder }) | Select-Object -First 1
    if (-not $source) { throw "Install-OpOfficeUpdate : aucune source de office\sources.json pour le dossier $($Item.folder)." }
    if (@($source.installedChannelIds) -notcontains $office.ChannelId) { return (ConvertTo-StepResult 'NotApplicable' "Canal absent du dépôt (Office installé sur le canal $($office.ChannelId), source $($source.id))." $null $before $before @()) }
    $missing = @($office.Languages | Where-Object { @($Item.languages) -notcontains $_ })
    if ($missing.Count -gt 0) { return (ConvertTo-StepResult 'NotApplicable' "Langue absente de la source : $($missing -join ', ')." $null $before $before @()) }

    $problems = @(Test-OpItemFileHash -Depot $depot -File @($Item.files))
    if ($problems.Count -gt 0) { return (ConvertTo-StepResult 'Error' "Source Office non conforme au manifeste, ODT non lancé : $($problems -join ' ')" $null $before $before @()) }

    $sourcePath = Join-Path $depot ([string]$Item.folder -replace '/', '\')
    $products = foreach ($product in @($office.Products)) {
        $lines = @('    <Product ID="{0}">' -f (ConvertTo-XmlText $product))
        $lines += @($office.Languages | ForEach-Object { '      <Language ID="{0}" />' -f (ConvertTo-XmlText $_) })
        $lines += '    </Product>'
        $lines -join "`r`n"
    }
    $template = Get-Content -LiteralPath (Join-Path (Get-OpPath -Name OfficeConfig -Root $Root) 'update.xml.template') -Raw -Encoding UTF8 -ErrorAction Stop
    $xml = $template.Replace('{{Channel}}', (ConvertTo-XmlText ([string]$source.channel))).Replace('{{SourcePath}}', (ConvertTo-XmlText $sourcePath)).Replace('{{ProductElements}}', (@($products) -join "`r`n"))
    try { [void][xml]$xml }
    catch { throw "XML de mise à jour d'Office invalide (update.xml.template) : $($_.Exception.Message)" }

    $setup = Join-Path (Get-OpPath -Name Odt -Root $Root) 'setup.exe'
    if (-not $PSCmdlet.ShouldProcess("$(@($office.Products) -join ', ') $before", "Mise à jour d'Office vers $available depuis $sourcePath")) { return }
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { return (ConvertTo-StepResult 'Error' "setup.exe absent de $(Split-Path -Path $setup -Parent)." $null $before $before @()) }

    $temp = Get-OpPath -Name ClientTemp
    New-Item -ItemType Directory -Force -Path $temp -ErrorAction Stop | Out-Null
    $config = Join-Path $temp "office-update_$($source.id).xml"
    [System.IO.File]::WriteAllText($config, $xml, (New-Object System.Text.UTF8Encoding $false))
    $timeout = [int]$Configuration.Settings.client.odtTimeoutMinutes
    Write-OpLog "$($Item.id) : setup.exe /configure, $(@($office.Products) -join ', ') ($(@($office.Languages) -join ', ')) $before vers $available, source $sourcePath."
    $start = Get-Date
    $run = Invoke-OpOfficeSetup -SetupPath $setup -ConfigPath $config -Mode configure -TimeoutMinutes $timeout -LogSearchDirectory @($env:TEMP) -SessionLogDirectory $LogDirectory -StepStart $start.AddMinutes(-1) -Confirm:$false
    $after = Get-OpOfficeInstallation
    $installed = $null
    if ($after) { $installed = $after.Version }
    $logs = @($run.OdtLogs)
    if ($run.TimedOut) { return (ConvertTo-StepResult 'Error' "Délai dépassé ($timeout min) ; version relevée après arrêt de l'ODT : $installed." $null $before $installed $logs) }
    if ($run.ExitCode -ne 0) { return (ConvertTo-StepResult 'Error' "L'ODT a renvoyé le code $($run.ExitCode), voir ses journaux." $run.ExitCode $before $installed $logs) }
    $v = $null
    if ($installed -and [version]::TryParse([string]$installed, [ref]$v) -and $v -ge [version]$available) {
        return (ConvertTo-StepResult 'UpToDate' "Office $before -> $installed." 0 $before $installed $logs)
    }
    ConvertTo-StepResult 'Error' "L'ODT a renvoyé 0 sans atteindre la version $available (version relevée : $installed)." 0 $before $installed $logs
}
