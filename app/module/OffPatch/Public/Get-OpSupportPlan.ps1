function Get-OpSupportPlan {
    <#
    .SYNOPSIS
        Prépare, en lecture seule, la copie d'OffPatch sur un support : contenu filtré, système de fichiers, espace.

    .DESCRIPTION
        Cahier des charges 7.4, étapes 1 à 3. Ne copie rien. Contenu : fichiers de l'outil (Lancer-OffPatch.cmd,
        offpatch.root, README.md, LICENSE, app\, config\, tools\) et éléments du manifeste des cibles et des sources
        Office retenues, chacun avec ses fichiers ; un élément dont un fichier manque au dépôt ou n'a pas la taille du
        manifeste est écarté, avec un avertissement. Les fichiers partagés ne comptent qu'une fois.
        Refus (Blocking) : lecteur absent ou pas prêt, même volume que l'outil, système de fichiers autre que NTFS
        ou exFAT (FAT32 : la cumulative Windows 11 x64 dépasse 4 Gio, R-12), espace libre insuffisant, dossiers app,
        config, tools ou depot étrangers à OffPatch (lecteur sans offpatch.root : la copie en miroir les viderait),
        rien à embarquer. L'espace demandé ne compte pas les fichiers déjà présents sur le support avec la bonne taille.
        Avertissement si le support fait moins du double du dépôt retenu : trop peu de marge pour la croissance des
        cumulatives (64 Go recommandés pour un dépôt complet, 32 Go pour un dépôt filtré).
        Renvoie Destination, Volume, Targets, OfficeSources, Items (éléments retenus du manifeste), Files (chemins
        relatifs à la racine et tailles), DepotBytes, ToolBytes, ToCopyBytes, Blocking, Warnings et CanPrepare.

    .PARAMETER Destination
        Dossier de destination sur le support, en général la racine du lecteur (E:\).

    .PARAMETER Targets
        Cibles Windows à embarquer (win11-x64…) ; par défaut, celles cochées dans settings.json.

    .PARAMETER OfficeSources
        Sources Office à embarquer (current…) ; par défaut, celles actives dans sources.json.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Get-OpSupportPlan -Destination F:\ -Targets win11-x64 -OfficeSources current
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [AllowEmptyCollection()][string[]]$Targets,
        [AllowEmptyCollection()][string[]]$OfficeSources,
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    if (-not $PSBoundParameters.ContainsKey('Targets') -or -not $PSBoundParameters.ContainsKey('OfficeSources')) {
        $selection = Get-OpDepotSelection -Root $Root
        if (-not $PSBoundParameters.ContainsKey('Targets')) { $Targets = @($selection.Targets) }
        if (-not $PSBoundParameters.ContainsKey('OfficeSources')) { $OfficeSources = @($selection.OfficeSources | Where-Object { $_.Enabled } | ForEach-Object { $_.Id }) }
    }
    $Targets = @($Targets | Where-Object { $_ })
    $OfficeSources = @($OfficeSources | Where-Object { $_ })
    $blocking = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $files = [ordered]@{}

    # Outil : fichiers de la racine et dossiers app, config, tools (journaux, rapports et dépôt n'en font pas partie).
    $toolBytes = [long]0
    foreach ($name in 'Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE') {
        $path = Join-Path $Root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $files[$name] = (Get-Item -LiteralPath $path).Length }
    }
    foreach ($folder in 'app', 'config', 'tools') {
        $path = Join-Path $Root $folder
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $path -Recurse -File)) { $files[$f.FullName.Substring($Root.TrimEnd('\').Length + 1)] = $f.Length }
    }
    foreach ($size in $files.Values) { $toolBytes += [long]$size }

    # Dépôt filtré : éléments des cibles et des sources retenues, complets au dépôt.
    $depot = Get-OpPath -Name Depot -Root $Root
    $items = New-Object System.Collections.Generic.List[object]
    $depotBytes = [long]0
    foreach ($m in @((Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)).items | Where-Object { $_ })) {
        if ($m.category -eq 'office-source') { $keep = $OfficeSources -contains (Split-Path -Leaf ([string]$m.folder)) }
        else { $keep = $m.PSObject.Properties['target'] -and ($Targets -contains ('{0}-{1}' -f $m.target.os, $m.target.arch)) }
        if (-not $keep) { continue }
        $itemFiles = @()
        if ($m.PSObject.Properties['files']) { $itemFiles = @($m.files | Where-Object { $_ }) }
        $bad = @($itemFiles | Where-Object {
                $info = Get-Item -LiteralPath (Join-Path $depot ([string]$_.path -replace '/', '\')) -ErrorAction SilentlyContinue
                -not $info -or $info.Length -ne [long]$_.size
            })
        if ($bad.Count -gt 0) {
            $warnings.Add("$($m.id) : $($bad.Count) fichier(s) absent(s) ou incomplet(s) au dépôt, élément non copié.")
            continue
        }
        $items.Add($m)
        foreach ($f in $itemFiles) {
            $relative = 'depot\' + ([string]$f.path -replace '/', '\')
            if (-not $files.Contains($relative)) { $files[$relative] = [long]$f.size; $depotBytes += [long]$f.size }
        }
    }
    if ($items.Count -eq 0) { $blocking.Add('Rien à embarquer : aucun élément complet du dépôt pour les cibles et les sources Office retenues.') }

    # Support : volume, système de fichiers, espace.
    $volume = $null
    $toCopy = [long]0
    try {
        $Destination = [System.IO.Path]::GetFullPath($Destination)
        $volume = Get-OpVolumeInfo -Path $Destination
    } catch {
        $blocking.Add("Destination invalide ($Destination) : $($_.Exception.Message)")
    }
    if ($volume) {
        $toolVolume = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Root))
        if (-not $volume.IsReady) { $blocking.Add("Lecteur $($volume.Root) absent ou pas prêt.") }
        elseif ($volume.Root -eq $toolVolume) { $blocking.Add("Le support doit être un autre lecteur que celui de l'outil ($toolVolume).") }
        else {
            if (@('NTFS', 'exFAT') -notcontains $volume.FileSystem) {
                $blocking.Add("Système de fichiers $($volume.FileSystem) refusé : NTFS ou exFAT requis (en FAT32, un fichier ne peut pas dépasser 4 Gio, et la cumulative Windows 11 x64 les dépasse).")
            }
            # La copie met app, config, tools et les dossiers du dépôt en miroir : sur un lecteur qui n'est pas déjà un
            # support OffPatch, des dossiers de ces noms seraient vidés.
            if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($Destination, 'offpatch.root')) -PathType Leaf)) {
                $foreign = @('app', 'config', 'tools', 'depot' | Where-Object { Test-Path -LiteralPath ([System.IO.Path]::Combine($Destination, $_)) })
                if ($foreign.Count -gt 0) { $blocking.Add("Le lecteur contient déjà des dossiers $($foreign -join ', ') qui n'appartiennent pas à OffPatch : la copie les remplacerait. Choisir un autre lecteur ou les déplacer.") }
            }
            foreach ($relative in $files.Keys) {
                $existing = Get-Item -LiteralPath ([System.IO.Path]::Combine($Destination, $relative)) -ErrorAction SilentlyContinue
                if (-not $existing -or $existing.Length -ne [long]$files[$relative]) { $toCopy += [long]$files[$relative] }
            }
            if ($toCopy -gt [long]$volume.FreeBytes) {
                $blocking.Add("Espace insuffisant sur $($volume.Root) : $(Format-OpSize $toCopy) à copier, $(Format-OpSize ([long]$volume.FreeBytes)) libres.")
            }
            # Marge : support d'au moins le double du dépôt retenu, ce qui retrouve les exemples de 7.4 (64 Go pour environ
            # 23 Gio, 32 Go pour environ 9 Gio). Règle simple, à revoir si les cumulatives grossissent plus vite.
            if ($depotBytes -gt 0 -and [long]$volume.TotalBytes -lt 2 * $depotBytes) {
                $warnings.Add("Support de $(Format-OpSize ([long]$volume.TotalBytes)) pour un dépôt de $(Format-OpSize $depotBytes) : peu de marge pour la croissance des cumulatives (64 Go recommandés pour un dépôt complet).")
            }
        }
    }

    [pscustomobject]@{
        Destination = $Destination; Volume = $volume; Targets = $Targets; OfficeSources = $OfficeSources
        Items = $items.ToArray(); Files = @($files.Keys | ForEach-Object { [pscustomobject]@{ Path = $_; Size = [long]$files[$_] } })
        DepotBytes = $depotBytes; ToolBytes = $toolBytes; ToCopyBytes = $toCopy
        Blocking = $blocking.ToArray(); Warnings = $warnings.ToArray(); CanPrepare = $blocking.Count -eq 0
    }
}
