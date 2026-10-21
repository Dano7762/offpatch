function Set-OpDepotSelection {
    <#
    .SYNOPSIS
        Enregistre les cibles et les sources Office cochées dans l'onglet Dépôt.

    .DESCRIPTION
        Cahier des charges 6.1, 6.3 et 9. Cibles : liste targets de settings.json. Sources Office : champ enabled
        (absent vaut true) et langues de chaque source de config\office\sources.json. Seules ces lignes changent :
        la présentation des fichiers, tenus à la main et suivis par git, est conservée. Le texte modifié est relu et
        doit redonner exactement les valeurs demandées, puis la configuration complète est contrôlée
        (Test-OpConfiguration) ; à la moindre anomalie, rien n'est écrit. Écriture atomique, UTF-8 sans BOM, fins de
        ligne du fichier conservées ; un fichier inchangé n'est pas réécrit.
        Renvoie Targets et OfficeSources (Id, Enabled, Languages) enregistrés.

    .PARAMETER Targets
        Cibles cochées (par exemple win11-x64).

    .PARAMETER OfficeSources
        Une entrée par source à régler : Id, Enabled, Languages. Les sources absentes de la liste ne changent pas.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Set-OpDepotSelection -Targets win11-x64, win10-x64 -OfficeSources @([pscustomobject]@{ Id = 'current'; Enabled = $true; Languages = @('fr-fr', 'en-us') })
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]]$Targets,
        [object[]]$OfficeSources = @(),
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    # Valeurs écrites telles quelles entre guillemets : forme contrôlée avant toute modification.
    foreach ($value in @($Targets) + @($OfficeSources | ForEach-Object { @($_.Languages) + $_.Id })) {
        if ([string]$value -notmatch '^[A-Za-z0-9-]+$') { throw "Valeur refusée pour la configuration : « $value »." }
    }
    function Format-Array([object[]]$Values) { '[' + ((@($Values) | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']' }
    function Get-Enabled($Source) { -not ($Source.PSObject.Properties['enabled'] -and $Source.enabled -eq $false) }

    $configuration = Get-OpConfiguration -Root $Root
    $settingsPath = Join-Path (Get-OpPath -Name Config -Root $Root) 'settings.json'
    $sourcesPath = Join-Path (Get-OpPath -Name OfficeConfig -Root $Root) 'sources.json'
    $settingsText = [System.IO.File]::ReadAllText($settingsPath)
    $sourcesText = [System.IO.File]::ReadAllText($sourcesPath)

    $pattern = New-Object System.Text.RegularExpressions.Regex '("targets"\s*:\s*)\[[^\]]*\]'
    if (-not $pattern.IsMatch($settingsText)) { throw 'settings.json : liste targets introuvable, configuration non modifiée.' }
    $newSettings = $pattern.Replace($settingsText, ('${1}' + (Format-Array $Targets)), 1)

    $newSources = $sourcesText
    $newLine = "`n"
    if ($sourcesText.Contains("`r`n")) { $newLine = "`r`n" }
    foreach ($wanted in @($OfficeSources)) {
        # Bloc de la source : de son identifiant à la fin de l'objet (une source ne contient pas d'objet imbriqué).
        $match = [regex]::Match($newSources, '"id"\s*:\s*"' + [regex]::Escape([string]$wanted.Id) + '"[^{}]*\}')
        if (-not $match.Success) { throw "sources.json : source $($wanted.Id) introuvable, configuration non modifiée." }
        $block = $match.Value
        $languages = [regex]::Match($block, '(?m)^([ \t]*)"languages"\s*:\s*\[[^\]]*\]')
        if (-not $languages.Success) { throw "sources.json : langues de la source $($wanted.Id) introuvables, configuration non modifiée." }
        $indent = $languages.Groups[1].Value
        $block = $block.Remove($languages.Index, $languages.Length).Insert($languages.Index, $indent + '"languages": ' + (Format-Array $wanted.Languages))
        $enabledText = ([string][bool]$wanted.Enabled).ToLowerInvariant()
        if ($block -match '"enabled"\s*:\s*(true|false)') { $block = $block -replace '"enabled"\s*:\s*(true|false)', ('"enabled": ' + $enabledText) }
        elseif (-not $wanted.Enabled) { $block = $block.Insert($block.IndexOf($indent + '"languages"'), $indent + '"enabled": false,' + $newLine) }
        $newSources = $newSources.Remove($match.Index, $match.Length).Insert($match.Index, $block)
    }

    # Relecture : le texte modifié doit redonner exactement les valeurs demandées.
    $settings = $newSettings | ConvertFrom-Json
    $sources = $newSources | ConvertFrom-Json
    if ((@($settings.targets) -join ',') -ne (@($Targets) -join ',')) { throw 'settings.json : relecture différente des cibles demandées, configuration non modifiée.' }
    foreach ($wanted in @($OfficeSources)) {
        $src = @($sources.sources | Where-Object { $_.id -eq $wanted.Id })[0]
        if ((Get-Enabled $src) -ne [bool]$wanted.Enabled -or (@($src.languages) -join ',') -ne (@($wanted.Languages) -join ',')) {
            throw "sources.json : relecture de la source $($wanted.Id) différente de la demande, configuration non modifiée."
        }
    }
    $configuration.Settings = $settings
    $configuration.OfficeSources = $sources
    $errors = @(Test-OpConfiguration -Configuration $configuration)
    if ($errors.Count -gt 0) { throw "Sélection refusée : $($errors -join ' ')" }

    $utf8 = New-Object System.Text.UTF8Encoding $false
    foreach ($file in @(@{ Path = $settingsPath; Old = $settingsText; New = $newSettings }, @{ Path = $sourcesPath; Old = $sourcesText; New = $newSources })) {
        if ($file.New -ceq $file.Old) { continue }
        if (-not $PSCmdlet.ShouldProcess($file.Path, 'Enregistrement de la sélection du dépôt')) { continue }
        $tmp = "$($file.Path).tmp"
        [System.IO.File]::WriteAllText($tmp, $file.New, $utf8)
        Move-Item -LiteralPath $tmp -Destination $file.Path -Force -ErrorAction Stop
        Write-OpLog "Sélection du dépôt enregistrée dans $($file.Path)."
    }
    [pscustomobject]@{
        Targets       = @($settings.targets)
        OfficeSources = @($sources.sources | ForEach-Object { [pscustomobject]@{ Id = $_.id; Enabled = (Get-Enabled $_); Languages = @($_.languages) } })
    }
}
