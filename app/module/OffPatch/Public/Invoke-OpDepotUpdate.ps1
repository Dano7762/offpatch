function Invoke-OpDepotUpdate {
    <#
    .SYNOPSIS
        Met à jour le dépôt ; avec -ListOnly, affiche seulement ce qui serait récupéré, sans rien télécharger.

    .DESCRIPTION
        Face Dépôt (cahier des charges 7.1). Charge la configuration et le manifeste, interroge le catalogue selon
        catalog-queries.json, ajoute les éléments épinglés et les définitions Defender, résout et contrôle chaque lien
        (requêtes HEAD, hôtes de allowedDomains), puis compare la taille des nouveautés à l'espace libre du volume du
        dépôt. -ListOnly s'arrête là : rien n'est téléchargé ni écrit, hormis le journal.
        Sans -ListOnly : arrêt avant tout téléchargement si l'espace manque ; sinon chaque fichier absent du dépôt
        est téléchargé, contrôlé et rangé (Save-OpDepotFile), une seule fois s'il est partagé, puis chaque élément
        complet est inscrit au manifeste, réécrit de façon atomique après chaque élément : une interruption ne perd
        que l'élément en cours, et le lancement suivant reprend là. Un élément dont un fichier est refusé ou échoue
        n'est pas inscrit ; les autres continuent. Les éléments déjà au manifeste sont gardés (la purge est une
        étape distincte).
        Renvoie un objet : ListOnly, Items (éléments de Get-OpDepotPlan), DownloadBytes (fichiers à télécharger,
        comptés une fois), DownloadCount, UnknownSizeCount, FreeBytes (volume du dépôt, $null si illisible),
        EnoughSpace, ErrorCount (liens refusés, puis éléments non inscrits), NewItems (éléments ajoutés au manifeste
        par ce lancement, résumé des nouveautés).

    .PARAMETER ListOnly
        Interroge le catalogue et contrôle les liens sans rien télécharger.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Invoke-OpDepotUpdate -ListOnly

    .EXAMPLE
        Invoke-OpDepotUpdate

    .EXAMPLE
        (Invoke-OpDepotUpdate).NewItems | Select-Object id, category, kb, version
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$ListOnly,
        [string]$Root,
        [datetime]$Now = (Get-Date)
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $mode = 'téléchargement'
    if ($ListOnly) { $mode = '-ListOnly' }
    try {
        $configuration = Get-OpConfiguration -Root $Root
        $manifestPath = Get-OpPath -Name Manifest -Root $Root
        $manifest = Read-OpManifest -Path $manifestPath
        Write-OpLog "Mise à jour du dépôt ($mode) : cibles $(@($configuration.Settings.targets) -join ', ')."
        $items = @(Get-OpDepotPlan -Configuration $configuration -Manifest $manifest -Now $Now)
    } catch {
        # Catalogue injoignable, page non reconnue, manifeste invalide : l'erreur est journalisée puis relancée.
        Write-OpLog -Level ERROR -Message "Mise à jour du dépôt ($mode) interrompue : $($_.Exception.Message)"
        throw
    }

    # Fichiers à télécharger, comptés une fois (une checkpoint jointe à plusieurs éléments, mpam-fe.exe x64 commun à
    # win11-x64 et win10-x64).
    $seen = @{}
    $bytes = [long]0
    $unknown = 0
    $errorCount = 0
    foreach ($item in $items) {
        foreach ($f in $item.Files) {
            if ($f.Error) {
                $errorCount++
                Write-OpLog -Level ERROR -Message "Dépôt, $($item.Id) : $($f.FileName) refusé. $($f.Error)"
                continue
            }
            if ($f.InDepot) {
                Write-OpLog "Dépôt, $($item.Id) : $($f.FileName) déjà au dépôt."
                continue
            }
            Write-OpLog "Dépôt, $($item.Id) : $($f.FileName) à télécharger ($(@($f.Hosts) -join ' -> '))."
            # Repère : l'URL finale, pas le nom (mpam-fe.exe porte le même nom pour x64 et ARM64).
            if ($seen.ContainsKey($f.Url)) { continue }
            $seen[$f.Url] = $true
            if ($null -eq $f.SizeBytes) { $unknown++ } else { $bytes += $f.SizeBytes }
        }
    }

    $free = Get-OpFreeSpace -Path (Get-OpPath -Name Depot -Root $Root)
    $enough = $null
    if ($null -ne $free) { $enough = ($bytes -le $free) }
    $summary = "Dépôt ({0}) : {1} fichier(s) à télécharger, {2:N0} octets" -f $mode, $seen.Count, $bytes
    if ($unknown -gt 0) { $summary += " (taille inconnue pour $unknown fichier(s))" }
    if ($null -ne $free) { $summary += ", espace libre {0:N0} octets" -f $free }
    Write-OpLog $summary
    if ($enough -eq $false) { Write-OpLog -Level WARN -Message ("Dépôt : espace insuffisant, il manque {0:N0} octets : la mise à jour s'arrêterait avant tout téléchargement." -f ($bytes - $free)) }
    if ($null -eq $free) { Write-OpLog -Level WARN -Message 'Dépôt : espace libre du volume illisible (chemin réseau ?).' }

    $result = [pscustomobject]@{
        ListOnly         = [bool]$ListOnly
        Items            = $items
        DownloadBytes    = $bytes
        DownloadCount    = $seen.Count
        UnknownSizeCount = $unknown
        FreeBytes        = $free
        EnoughSpace      = $enough
        ErrorCount       = $errorCount
        NewItems         = @()
    }
    if ($ListOnly) { return $result }
    if ($enough -eq $false) {
        throw ("Mise à jour du dépôt arrêtée avant tout téléchargement : espace insuffisant, il manque {0:N0} octets." -f ($bytes - $free))
    }
    if (-not $PSCmdlet.ShouldProcess((Get-OpPath -Name Depot -Root $Root), 'Téléchargement des nouveautés et mise à jour du manifeste')) { return $result }

    # Entrées de fichier déjà au manifeste : par nom (il porte le SHA-1 publié), ou, pour mpam-fe.exe dont le nom ne
    # change jamais, par architecture et version.
    function Find-DepotEntry($Item, $File) {
        foreach ($m in @($manifest.items)) {
            if ($null -eq $m.PSObject.Properties['files']) { continue }
            if ($Item.Category -eq 'defender') {
                if ($m.category -eq 'defender' -and $m.target.arch -eq ($Item.Target -split '-')[1] -and [string]$m.version -eq [string]$Item.Version) { return @($m.files)[0] }
                continue
            }
            foreach ($e in @($m.files)) {
                if ((([string]$e.path -split '[\\/]')[-1]) -eq $File.FileName) { return $e }
            }
        }
        $null
    }

    $toolVersion = $null
    if ($MyInvocation.MyCommand.Module) { $toolVersion = [string]$MyInvocation.MyCommand.Module.Version }
    $downloaded = @{}
    $new = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        $entries = New-Object System.Collections.Generic.List[object]
        $failure = $null
        foreach ($f in $item.Files) {
            if ($f.Error) { $failure = $f.Error; break }
            if ($f.InDepot) {
                $entry = Find-DepotEntry $item $f
                if (-not $entry) { $failure = "$($f.FileName) annoncé au dépôt mais absent du manifeste."; break }
                $entries.Add($entry)
                continue
            }
            if (-not $downloaded.ContainsKey($f.Url)) {
                try {
                    $downloaded[$f.Url] = Save-OpDepotFile -Item $item -File $f -Configuration $configuration -Root $Root -Confirm:$false
                } catch {
                    $downloaded[$f.Url] = $_.Exception.Message
                }
            }
            if ($downloaded[$f.Url] -is [string]) { $failure = $downloaded[$f.Url]; break }
            $entries.Add($downloaded[$f.Url])
        }
        if ($failure) {
            $errorCount++
            Write-OpLog -Level ERROR -Message "Dépôt, $($item.Id) : élément non inscrit au manifeste. $failure"
            continue
        }

        $manifestItem = ConvertTo-OpManifestItem -Item $item -Files $entries.ToArray() -Configuration $configuration
        $isNew = -not @($manifest.items | Where-Object { $_.id -eq $manifestItem.id })
        $manifest.items = @(@($manifest.items | Where-Object { $_.id -ne $manifestItem.id }) + $manifestItem)
        try {
            Save-OpManifest -Manifest $manifest -Path $manifestPath -ToolVersion $toolVersion -Confirm:$false
        } catch {
            Write-OpLog -Level ERROR -Message "Mise à jour du dépôt interrompue : manifeste non écrit. $($_.Exception.Message)"
            throw
        }
        if ($isNew) {
            $new.Add($manifestItem)
            Write-OpLog "Dépôt : nouveauté inscrite au manifeste, $($manifestItem.id)."
        }
    }

    $result.ErrorCount = $errorCount
    $result.NewItems = $new.ToArray()
    Write-OpLog ("Mise à jour du dépôt terminée : {0} nouveauté(s), {1} erreur(s)." -f $new.Count, $errorCount)
    $result
}
