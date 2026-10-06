function Test-OpConfiguration {
    <#
    .SYNOPSIS
        Contrôle la configuration chargée (settings, catalog-queries, pinned-items, sources Office) et renvoie la
        liste des anomalies, en français ; liste vide si tout est cohérent.

    .DESCRIPTION
        Règles tirées du cahier des charges (6.1 à 6.4, 7.3, 8.2) : versions de schéma, cibles connues, rétention par
        cible, valeurs du client, niveau du journal, empreintes de racine, hôtes exacts de allowedDomains, liens
        downloadPages en https sur un hôte autorisé, recherches du catalogue (catégories, motifs, règles de sélection,
        dépendances), éléments épinglés (lien, SHA-1, builds), sources Office (un canal par source, dossier, langues,
        identifiants de canal installé uniques).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $knownTargets = 'win11-x64', 'win11-arm64', 'win10-x64'
    $categories = 'windows-lcu', 'windows-checkpoint', 'windows-ekb', 'windows-ssu', 'dotnet', 'defender-platform', 'defender', 'office-source'
    $picks = 'latestMonth', 'highestUbr', 'highestUbrFromReleaseInformation', 'highestVersion'
    $hostPattern = '^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$'

    function Test-Property([object]$Object, [string]$Name) {
        $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
    }
    function Test-Regex([string]$Pattern) {
        try { [void][regex]::new($Pattern); $true } catch { $false }
    }

    # settings.json
    $s = $Configuration.Settings
    if ([int]$s.schemaVersion -ne 1) { $errors.Add("settings.json : schemaVersion $($s.schemaVersion) non pris en charge (attendu : 1).") }
    $targets = @($s.targets)
    if ($targets.Count -eq 0) { $errors.Add('settings.json : aucune cible dans targets.') }
    foreach ($t in $targets) {
        if ($knownTargets -notcontains $t) { $errors.Add("settings.json : cible inconnue « $t » (connues : $($knownTargets -join ', ')).") ; continue }
        if (-not (Test-Property $s.retention.windowsMonths $t)) { $errors.Add("settings.json : retention.windowsMonths n'a pas de valeur pour la cible $t.") }
        elseif ([int]$s.retention.windowsMonths.$t -lt 1) { $errors.Add("settings.json : retention.windowsMonths.$t doit valoir au moins 1.") }
    }
    if ([int]$s.retention.officeVersions -lt 1) { $errors.Add('settings.json : retention.officeVersions doit valoir au moins 1.') }
    $client = $s.client
    foreach ($rule in @(@('minFreeSpaceGB', 1), @('maxAutoReboots', 1), @('rebootCountdownSeconds', 0), @('staleDepotWarningDays', 1), @('odtTimeoutMinutes', 1))) {
        if (-not (Test-Property $client $rule[0])) { $errors.Add("settings.json : client.$($rule[0]) absent.") }
        elseif ([int]$client.($rule[0]) -lt $rule[1]) { $errors.Add("settings.json : client.$($rule[0]) doit valoir au moins $($rule[1]).") }
    }
    if (-not (Test-Property $client 'createRestorePointBeforeSession') -or $client.createRestorePointBeforeSession -isnot [bool]) {
        $errors.Add('settings.json : client.createRestorePointBeforeSession doit valoir true ou false.')
    }
    if (@('DEBUG', 'INFO', 'WARN', 'ERROR') -notcontains $s.logging.level) { $errors.Add("settings.json : logging.level « $($s.logging.level) » inconnu (DEBUG, INFO, WARN, ERROR).") }
    $thumbprints = @($s.integrity.trustedRootThumbprints)
    if ($thumbprints.Count -eq 0) { $errors.Add('settings.json : integrity.trustedRootThumbprints est vide.') }
    foreach ($tp in $thumbprints) { if ($tp -notmatch '^[0-9A-Fa-f]{40}$') { $errors.Add("settings.json : empreinte de racine invalide « $tp » (40 caractères hexadécimaux).") } }
    $allowed = @($s.allowedDomains)
    foreach ($d in $allowed) { if ($d -notmatch $hostPattern) { $errors.Add("settings.json : allowedDomains doit contenir des noms d'hôte exacts, sans schéma ni joker : « $d ».") } }
    $links = New-Object System.Collections.Generic.List[string]
    if (Test-Property $s 'downloadPages') {
        foreach ($p in @($s.downloadPages.defenderDefinitions.PSObject.Properties)) { $links.Add([string]$p.Value) }
        $links.Add([string]$s.downloadPages.officeDeploymentToolPage)
        foreach ($t in $targets) {
            $arch = ($t -split '-')[1]
            if (-not (Test-Property $s.downloadPages.defenderDefinitions $arch)) { $errors.Add("settings.json : downloadPages.defenderDefinitions n'a pas de lien pour l'architecture $arch (cible $t).") }
        }
    } else { $errors.Add('settings.json : downloadPages absent.') }
    foreach ($l in $links) {
        $uri = $null
        if (-not [uri]::TryCreate($l, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { $errors.Add("settings.json : lien downloadPages invalide ou non https : « $l ».") }
        elseif ($allowed -notcontains $uri.Host.ToLowerInvariant()) { $errors.Add("settings.json : l'hôte de « $l » n'est pas dans allowedDomains.") }
    }

    # catalog-queries.json
    $q = $Configuration.CatalogQueries
    if ([int]$q.schemaVersion -ne 1) { $errors.Add("catalog-queries.json : schemaVersion $($q.schemaVersion) non pris en charge (attendu : 1).") }
    if ([int]$q.monthsToSearch -lt 1) { $errors.Add('catalog-queries.json : monthsToSearch doit valoir au moins 1.') }
    foreach ($t in $targets) {
        if (-not (Test-Property $q.targets $t)) { $errors.Add("catalog-queries.json : aucune recherche pour la cible $t.") ; continue }
        foreach ($entry in @($q.targets.$t)) {
            $label = "catalog-queries.json, $t / $($entry.category)"
            if ($categories -notcontains $entry.category) { $errors.Add("$label : catégorie inconnue.") }
            if (@($entry.searches).Count -eq 0) { $errors.Add("$label : aucune recherche (searches).") }
            foreach ($field in 'includeTitlePattern', 'excludeTitlePattern') {
                if (-not $entry.$field -or -not (Test-Regex $entry.$field)) { $errors.Add("$label : $field absent ou invalide.") }
            }
            if ((Test-Property $entry 'fileNamePattern') -and -not (Test-Regex $entry.fileNamePattern)) { $errors.Add("$label : fileNamePattern invalide.") }
            if ($picks -notcontains $entry.pick) { $errors.Add("$label : règle de sélection « $($entry.pick) » inconnue ($($picks -join ', ')).") }
            foreach ($dep in @($entry.prerequisites) + @($entry.runsAfter)) {
                if ($dep -and $categories -notcontains $dep) { $errors.Add("$label : dépendance vers une catégorie inconnue « $dep ».") }
            }
        }
    }

    # pinned-items.json
    $ids = @{}
    foreach ($item in @($Configuration.PinnedItems.items)) {
        $label = "pinned-items.json, $($item.id)"
        if ($ids.ContainsKey($item.id)) { $errors.Add("$label : identifiant en double.") } else { $ids[$item.id] = $true }
        if ($categories -notcontains $item.category) { $errors.Add("$label : catégorie inconnue « $($item.category) ».") }
        $uri = $null
        if (-not [uri]::TryCreate([string]$item.url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { $errors.Add("$label : lien invalide ou non https.") }
        elseif ($allowed -notcontains $uri.Host.ToLowerInvariant()) { $errors.Add("$label : l'hôte du lien n'est pas dans allowedDomains.") }
        if ($item.sha1 -notmatch '^[0-9a-f]{40}$') { $errors.Add("$label : sha1 invalide (40 caractères hexadécimaux en minuscules).") }
        elseif ($uri -and $uri.AbsolutePath -notmatch ('_' + $item.sha1 + '\.\w+$')) { $errors.Add("$label : le sha1 ne correspond pas à l'empreinte du nom de fichier.") }
        if (@($item.appliesToBaseBuilds).Count -eq 0) { $errors.Add("$label : appliesToBaseBuilds est vide.") }
    }

    # office/sources.json : une source par canal, ses langues, les identifiants de canal lus dans le registre (8.3)
    $o = $Configuration.OfficeSources
    if ([int]$o.schemaVersion -ne 1) { $errors.Add("sources.json : schemaVersion $($o.schemaVersion) non pris en charge (attendu : 1).") }
    $sourceIds = @{}
    $channels = @{}
    $channelIds = @{}
    foreach ($src in @($o.sources)) {
        $label = "sources.json, $($src.id)"
        if (-not $src.id) { $errors.Add('sources.json : source sans identifiant.') ; continue }
        if ($sourceIds.ContainsKey($src.id)) { $errors.Add("$label : identifiant en double.") } else { $sourceIds[$src.id] = $true }
        if (-not $src.channel) { $errors.Add("$label : channel absent.") }
        elseif ($channels.ContainsKey($src.channel)) { $errors.Add("$label : canal $($src.channel) déjà couvert par une autre source.") } else { $channels[$src.channel] = $true }
        if ([string]$src.folder -notmatch '^office/[a-z0-9]+$') { $errors.Add("$label : folder doit être de la forme office/<nom>.") }
        $languages = @($src.languages)
        if ($languages.Count -eq 0) { $errors.Add("$label : aucune langue.") }
        foreach ($lang in $languages) { if ($lang -notmatch '^[a-z]{2}-[a-z]{2}$') { $errors.Add("$label : langue « $lang » invalide (forme xx-xx).") } }
        $ids = @($src.installedChannelIds)
        if ($ids.Count -eq 0) { $errors.Add("$label : installedChannelIds est vide : le canal installé ne pourrait pas être reconnu.") }
        foreach ($id in $ids) {
            if ($id -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { $errors.Add("$label : identifiant de canal « $id » invalide (GUID en minuscules).") }
            elseif ($channelIds.ContainsKey($id)) { $errors.Add("$label : identifiant de canal $id déjà attribué à une autre source.") } else { $channelIds[$id] = $true }
        }
    }

    # Une chaîne par anomalie ; l'appelant regroupe le résultat avec @().
    $errors.ToArray()
}
