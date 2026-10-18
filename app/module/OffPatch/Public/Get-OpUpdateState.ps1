function Get-OpUpdateState {
    <#
    .SYNOPSIS
        Détecte, en lecture seule, l'état de chaque mise à jour du dépôt sur ce PC.

    .DESCRIPTION
        Cahier des charges 8.3 (R-02, R-05, R-06, R-08, R-09). Éléments du manifeste de la cible du PC, et sources
        Office. États : UpToDate, Pending, NotApplicable, MissingFromDepot, Error. SkippedPrerequisite dépend de
        l'enchaînement des étapes (UBR projeté, minUbr) : il est posé par le planificateur, pas ici.
          - windows-lcu : non applicable si la build courante n'est pas dans baseBuilds ; à jour si UBR ≥
            resultingUbr. Seule la plus récente du dépôt peut être à installer ; une plus ancienne (repli, 7.3) est à
            jour ou non applicable.
          - windows-checkpoint : applicable aux builds de base des cumulatives qui l'exigent ; à jour si UBR ≥ son
            resultingUbr (catalog-queries.json, checkpointUbr) ; sans resultingUbr : Error.
          - windows-ssu : à installer si la build est dans baseBuilds et l'UBR inférieur à applyBelowUbr.
          - windows-ekb : non applicable si windows.includeEnablementPackage est faux ou si la build n'est pas dans
            baseBuilds (déjà en version cible, autre branche) ; à installer sinon (minUbr : planificateur).
          - dotnet : non applicable si la build n'est pas dans baseBuilds (une cumulative par version de Windows 11,
            R-05) ; fichier choisi par la valeur Release de .NET Framework 4 (netRelease) quand il y en a plusieurs ;
            à jour si la liste DISM (Get-WindowsPackage -Online) contient le paquet de même nom, Installed, de version
            ≥ ; même règle de repli que les cumulatives.
          - defender-platform, defender : applicables si Get-MpComputerStatus répond et que AMRunningMode vaut
            Normal, Passive Mode ou EDR Block Mode (plateforme ancienne sans AMRunningMode : AMServiceEnabled et
            AntivirusEnabled vrais, Get-OpDefenderRunningMode) ; non applicables sinon, jamais en erreur ; à jour si
            AMProductVersion, resp. AntivirusSignatureVersion, ≥ version du dépôt.
          - office-source : aucun Office Click-to-Run, Office 2016/2019 (endOfSupport), Office 32 bits (source du
            dépôt en 64 bits), canal absent du dépôt ou langue absente de la source : NotApplicable ; source attendue absente du manifeste ou du support :
            MissingFromDepot ; à jour si la version de fichier ≥ version de la source et égale à VersionToReport.
        Une cumulative, .NET ou Defender absente du manifeste pour la cible donne une ligne MissingFromDepot sans
        identifiant ; un élément à installer dont un fichier manque sur le support aussi.
        Renvoie Id, Category, State, Reason, Installed (état relevé sur le PC) et Available (version du dépôt).

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER SystemInfo
        Relevé de Get-OpSystemInfo déjà fait ; relu sinon.

    .EXAMPLE
        Get-OpUpdateState | Format-Table Category, Id, State, Reason -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [pscustomobject]$SystemInfo
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    if (-not $SystemInfo) { $SystemInfo = Get-OpSystemInfo -Root $Root }
    $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)
    $depot = Get-OpPath -Name Depot -Root $Root
    $build = [int]$SystemInfo.CurrentBuild
    $ubr = [int]$SystemInfo.Ubr
    $os, $arch = ([string]$SystemInfo.Target) -split '-', 2

    function Get-Prop($Object, [string]$Name) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        $null
    }
    function ConvertTo-Version($Text) {
        $v = $null
        if ([version]::TryParse(([string]$Text).Trim(), [ref]$v)) { return $v }
        $null
    }
    function ConvertTo-State($Item, [string]$Category, [string]$State, [string]$Reason, $Installed, $Available) {
        $id = $null
        if ($Item) { $id = $Item.id }
        [pscustomobject]@{ Id = $id; Category = $Category; State = $State; Reason = $Reason; Installed = $Installed; Available = $Available }
    }
    # Lectures du PC, faites une seule fois et seulement si une catégorie en a besoin.
    $facts = @{}
    function Get-Fact([string]$Key, [scriptblock]$Read) {
        if (-not $facts.ContainsKey($Key)) {
            try { $facts[$Key] = [pscustomobject]@{ Value = (& $Read); Error = $null } }
            catch { $facts[$Key] = [pscustomobject]@{ Value = $null; Error = $_.Exception.Message } }
        }
        $facts[$Key]
    }
    # Plus récent d'abord : la tête de liste est le seul candidat à l'installation, les autres sont des replis.
    function Get-NewestFirst([object[]]$Items, [scriptblock]$Key) {
        @($Items | Sort-Object -Property @{ Expression = $Key; Descending = $true }, @{ Expression = { [string](Get-Prop $_ 'releaseDate') }; Descending = $true })
    }

    $mine = @($manifest.items | Where-Object { $_ -and $_.category -ne 'office-source' -and (Get-Prop $_.target 'os') -eq $os -and (Get-Prop $_.target 'arch') -eq $arch })
    $results = New-Object System.Collections.Generic.List[object]
    function Add-State($State) { $results.Add($State) }

    foreach ($category in 'windows-lcu', 'dotnet', 'defender-platform', 'defender') {
        if (-not @($mine | Where-Object { $_.category -eq $category })) {
            Add-State (ConvertTo-State $null $category 'MissingFromDepot' "Aucun élément $category au dépôt pour la cible $($SystemInfo.Target)." $null $null)
        }
    }

    # Cumulatives Windows.
    $lcus = @(Get-NewestFirst @($mine | Where-Object { $_.category -eq 'windows-lcu' }) { [int](Get-Prop $_ 'resultingUbr') })
    $lcuCandidate = @($lcus | Where-Object { @(Get-Prop $_ 'baseBuilds') -contains $build }) | Select-Object -First 1
    foreach ($item in $lcus) {
        $target = [int](Get-Prop $item 'resultingUbr')
        $available = "$build.$target"
        if (@(Get-Prop $item 'baseBuilds') -notcontains $build) { Add-State (ConvertTo-State $item 'windows-lcu' 'NotApplicable' "Build $build absente de baseBuilds ($(@(Get-Prop $item 'baseBuilds') -join ', '))." "$build.$ubr" $available) }
        elseif ($ubr -ge $target) { Add-State (ConvertTo-State $item 'windows-lcu' 'UpToDate' "UBR $ubr ≥ $target." "$build.$ubr" $available) }
        elseif ($item -ne $lcuCandidate) { Add-State (ConvertTo-State $item 'windows-lcu' 'NotApplicable' "Repli : $($lcuCandidate.id), plus récente, est au dépôt." "$build.$ubr" $available) }
        else { Add-State (ConvertTo-State $item 'windows-lcu' 'Pending' "UBR $ubr < $target." "$build.$ubr" $available) }
    }

    foreach ($item in @($mine | Where-Object { $_.category -eq 'windows-checkpoint' })) {
        $builds = @($lcus | Where-Object { $p = @(Get-Prop $_ 'prerequisites'); $p -contains $item.id -or $p -contains 'windows-checkpoint' } | ForEach-Object { @(Get-Prop $_ 'baseBuilds') } | Sort-Object -Unique)
        $target = Get-Prop $item 'resultingUbr'
        if ($builds -notcontains $build) { Add-State (ConvertTo-State $item 'windows-checkpoint' 'NotApplicable' "Aucune cumulative du dépôt ne l'exige pour la build $build." "$build.$ubr" $null) }
        elseif ($null -eq $target) { Add-State (ConvertTo-State $item 'windows-checkpoint' 'Error' 'UBR de la checkpoint inconnu : compléter checkpointUbr (catalog-queries.json) puis mettre à jour le dépôt.' "$build.$ubr" $null) }
        elseif ($ubr -ge [int]$target) { Add-State (ConvertTo-State $item 'windows-checkpoint' 'UpToDate' "UBR $ubr ≥ $target." "$build.$ubr" "$build.$target") }
        else { Add-State (ConvertTo-State $item 'windows-checkpoint' 'Pending' "UBR $ubr < $target." "$build.$ubr" "$build.$target") }
    }

    foreach ($item in @($mine | Where-Object { $_.category -eq 'windows-ssu' })) {
        $below = Get-Prop $item 'applyBelowUbr'
        if (@(Get-Prop $item 'baseBuilds') -notcontains $build -or $null -eq $below) { Add-State (ConvertTo-State $item 'windows-ssu' 'NotApplicable' "Build $build non concernée." "$build.$ubr" $null) }
        elseif ($ubr -ge [int]$below) { Add-State (ConvertTo-State $item 'windows-ssu' 'NotApplicable' "UBR $ubr ≥ $below : pile de maintenance déjà à niveau." "$build.$ubr" $null) }
        else { Add-State (ConvertTo-State $item 'windows-ssu' 'Pending' "UBR $ubr < $below." "$build.$ubr" $null) }
    }

    foreach ($item in @($mine | Where-Object { $_.category -eq 'windows-ekb' })) {
        $resulting = Get-Prop $item 'resultingBuild'
        if (-not $configuration.Settings.windows.includeEnablementPackage) { Add-State (ConvertTo-State $item 'windows-ekb' 'NotApplicable' 'Option windows.includeEnablementPackage désactivée.' "$build.$ubr" $resulting) }
        elseif (@(Get-Prop $item 'baseBuilds') -notcontains $build) { Add-State (ConvertTo-State $item 'windows-ekb' 'NotApplicable' "Build $build non concernée (déjà en $resulting ou autre branche)." "$build.$ubr" $resulting) }
        else { Add-State (ConvertTo-State $item 'windows-ekb' 'Pending' "Passage en build $resulting ; prérequis UBR ≥ $(Get-Prop $item 'minUbr')." "$build.$ubr" $resulting) }
    }

    # .NET : une cumulative par version de Windows 11 depuis octobre 2026 (baseBuilds, R-05) ; fichier selon Release
    # (Windows 10), puis paquet DISM.
    function Test-ForBuild($Item) {
        $builds = @(Get-Prop $Item 'baseBuilds' | Where-Object { $null -ne $_ })
        $builds.Count -eq 0 -or $builds -contains $build
    }
    $allDotnets = @($mine | Where-Object { $_.category -eq 'dotnet' })
    foreach ($item in @($allDotnets | Where-Object { -not (Test-ForBuild $_) })) {
        Add-State (ConvertTo-State $item 'dotnet' 'NotApplicable' "Build $build absente de baseBuilds ($(@(Get-Prop $item 'baseBuilds') -join ', '))." $null $null)
    }
    $dotnets = @(Get-NewestFirst @($allDotnets | Where-Object { Test-ForBuild $_ }) { [string](Get-Prop $_ 'releaseDate') })
    if ($allDotnets.Count -gt 0 -and $dotnets.Count -eq 0) {
        Add-State (ConvertTo-State $null 'dotnet' 'MissingFromDepot' "Aucun élément dotnet au dépôt pour la build $build." $null $null)
    }
    foreach ($item in $dotnets) {
        $files = @($item.files)
        $file = $files[0]
        if (@($files | Where-Object { Get-Prop $_ 'netRelease' }).Count -gt 0) {
            $release = Get-Fact 'NetRelease' { [int](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release }
            $file = $null
            if (-not $release.Error) {
                $file = @($files | Where-Object { $r = Get-Prop $_ 'netRelease'; $r -and $release.Value -ge [int]$r.min -and ($null -eq (Get-Prop $r 'max') -or $release.Value -le [int]$r.max) }) | Select-Object -First 1
            }
            if (-not $file) {
                Add-State (ConvertTo-State $item 'dotnet' 'NotApplicable' ".NET Framework 4.8 ou 4.8.1 absent (Release : $(if ($release.Error) { 'illisible' } else { $release.Value }))." $release.Value $null)
                continue
            }
        }
        $package = Get-Prop $file 'package'
        if (-not $package) { Add-State (ConvertTo-State $item 'dotnet' 'Error' 'Paquet du .msu inconnu (manifeste sans package).' $null $null); continue }
        $packages = Get-Fact 'DismPackages' { @(Get-WindowsPackage -Online -ErrorAction Stop) }
        if ($packages.Error) { Add-State (ConvertTo-State $item 'dotnet' 'Error' "Liste des paquets DISM illisible : $($packages.Error)" $null $package.version); continue }
        $installed = @($packages.Value | Where-Object { ([string]$_.PackageName -split '~')[0] -eq $package.name -and [string]$_.PackageState -eq 'Installed' } |
                ForEach-Object { ConvertTo-Version (([string]$_.PackageName -split '~')[-1]) } | Where-Object { $_ } | Sort-Object -Descending) | Select-Object -First 1
        $wanted = ConvertTo-Version $package.version
        if ($installed -and $wanted -and $installed -ge $wanted) { Add-State (ConvertTo-State $item 'dotnet' 'UpToDate' "$($package.name) $installed installé." "$installed" $package.version) }
        elseif ($item -ne $dotnets[0]) { Add-State (ConvertTo-State $item 'dotnet' 'NotApplicable' "Repli : $($dotnets[0].id), plus récente, est au dépôt." "$installed" $package.version) }
        else {
            # Installé mais pas encore appliqué (3010) : toujours à installer jusqu'au redémarrage, motif explicite.
            $waiting = @($packages.Value | Where-Object { ([string]$_.PackageName -split '~')[0] -eq $package.name -and [string]$_.PackageState -eq 'InstallPending' } |
                    ForEach-Object { ConvertTo-Version (([string]$_.PackageName -split '~')[-1]) } | Where-Object { $_ -and $wanted -and $_ -ge $wanted }) | Select-Object -First 1
            $text = "$($package.name) $(if ($installed) { "$installed installé" } else { 'absent' })."
            if ($waiting) { $text = "$($package.name) $waiting en attente de redémarrage (InstallPending)." }
            Add-State (ConvertTo-State $item 'dotnet' 'Pending' $text "$installed" $package.version)
        }
    }

    # Defender (R-06) : jamais en erreur.
    foreach ($pair in @(@('defender-platform', 'AMProductVersion'), @('defender', 'AntivirusSignatureVersion'))) {
        $items = @(Get-NewestFirst @($mine | Where-Object { $_.category -eq $pair[0] }) { ConvertTo-Version (Get-Prop $_ 'version') })
        if ($items.Count -eq 0) { continue }
        $status = Get-Fact 'Defender' { Get-MpComputerStatus -ErrorAction Stop }
        $mode = Get-OpDefenderRunningMode $status.Value
        foreach ($item in $items) {
            $available = [string](Get-Prop $item 'version')
            if ($status.Error) { Add-State (ConvertTo-State $item $pair[0] 'NotApplicable' "Defender ne répond pas (Get-MpComputerStatus : $($status.Error))." $null $available); continue }
            if (@('Normal', 'Passive Mode', 'EDR Block Mode') -notcontains $mode) { Add-State (ConvertTo-State $item $pair[0] 'NotApplicable' "Defender désactivé (AMRunningMode : $(if ($mode) { $mode } else { 'absent' }))." $null $available); continue }
            $installed = ConvertTo-Version (Get-Prop $status.Value $pair[1])
            $wanted = ConvertTo-Version $available
            if ($installed -and $wanted -and $installed -ge $wanted) { Add-State (ConvertTo-State $item $pair[0] 'UpToDate' "$($pair[1]) $installed ≥ $available." "$installed" $available) }
            elseif ($item -ne $items[0]) { Add-State (ConvertTo-State $item $pair[0] 'NotApplicable' "Repli : $($items[0].id), plus récente, est au dépôt." "$installed" $available) }
            else { Add-State (ConvertTo-State $item $pair[0] 'Pending' "$($pair[1]) $installed < $available." "$installed" $available) }
        }
    }

    # Office (8.3, 8.5, R-08).
    $office = $SystemInfo.Office
    $sources = $configuration.OfficeSources
    if (-not $office) { Add-State (ConvertTo-State $null 'office-source' 'NotApplicable' 'Aucun Office Click-to-Run.' $null $null) }
    else {
        $installedText = "$(@($office.Products) -join ', ') $($office.Version)"
        $pattern = [string](Get-Prop $sources.endOfSupport 'productIdPattern')
        $source = @($sources.sources | Where-Object { @($_.installedChannelIds) -contains $office.ChannelId }) | Select-Object -First 1
        $item = $null
        if ($source) { $item = @($manifest.items | Where-Object { $_ -and $_.category -eq 'office-source' -and (Get-Prop $_ 'folder') -eq $source.folder }) | Select-Object -First 1 }
        $missingLanguages = @()
        if ($item) { $missingLanguages = @($office.Languages | Where-Object { @($item.languages) -notcontains $_ }) }
        if ($pattern -and @($office.Products | Where-Object { $_ -match $pattern })) { Add-State (ConvertTo-State $null 'office-source' 'NotApplicable' ([string](Get-Prop $sources.endOfSupport 'reason')) $installedText $null) }
        elseif ([string](Get-Prop $office 'Platform') -eq 'x86') { Add-State (ConvertTo-State $null 'office-source' 'NotApplicable' 'Office 32 bits : la source du dépôt est en 64 bits.' $installedText $null) }
        elseif (-not $source) { Add-State (ConvertTo-State $null 'office-source' 'NotApplicable' "Canal absent du dépôt (identifiant $($office.ChannelId))." $installedText $null) }
        elseif (-not $item) { Add-State (ConvertTo-State $null 'office-source' 'MissingFromDepot' "Source $($source.id) absente du manifeste." $installedText $null) }
        elseif ($missingLanguages.Count -gt 0) { Add-State (ConvertTo-State $item 'office-source' 'NotApplicable' "Langue absente de la source $($source.id) : $($missingLanguages -join ', ')." $installedText $item.version) }
        elseif (-not (ConvertTo-Version $office.Version)) { Add-State (ConvertTo-State $item 'office-source' 'Error' 'Version d''Office illisible (WINWORD.EXE, EXCEL.EXE, POWERPNT.EXE).' $installedText $item.version) }
        else {
            $note = ''
            if ($office.ChannelMismatch) { $note = " Canal : CDNBaseUrl ($($office.CdnChannelId)) et UpdateChannel ($($office.UpdateChannelId)) diffèrent, UpdateChannel retenu." }
            $reported = ConvertTo-Version $office.VersionToReport
            $officeVersion = ConvertTo-Version $office.Version
            if ($reported -and $reported -ne $officeVersion) { Add-State (ConvertTo-State $item 'office-source' 'Pending' "VersionToReport $reported diffère de la version des applications $($office.Version) : mise à jour relancée.$note" $installedText $item.version) }
            elseif ($officeVersion -ge (ConvertTo-Version $item.version)) { Add-State (ConvertTo-State $item 'office-source' 'UpToDate' "Version $($office.Version) ≥ $($item.version).$note" $installedText $item.version) }
            else { Add-State (ConvertTo-State $item 'office-source' 'Pending' "Version $($office.Version) < $($item.version).$note" $installedText $item.version) }
        }
    }

    # Élément à installer dont un fichier manque sur le support.
    foreach ($r in @($results | Where-Object { $_.State -eq 'Pending' -and $_.Id })) {
        $item = @($manifest.items | Where-Object { $_ -and $_.id -eq $r.Id })[0]
        $missing = @($item.files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $depot ([string]$_.path -replace '/', '\')) -PathType Leaf) })
        if ($missing.Count -gt 0) {
            $r.State = 'MissingFromDepot'
            $r.Reason = "Fichier absent du support : $($missing[0].path)$(if ($missing.Count -gt 1) { " (et $($missing.Count - 1) autre(s))" })."
        }
    }
    $results.ToArray()
}
