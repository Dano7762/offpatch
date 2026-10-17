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
        n'est pas inscrit ; les autres continuent. Si une source Office est configurée, l'ODT de tools\odt est
        comparé à la dernière version publiée (Get-OpOdtPlan) et remplacé s'il est plus ancien (Save-OpOdt) ; son
        échec compte comme une erreur sans arrêter le reste. Chaque source Office est ensuite téléchargée ou
        complétée par setup.exe /download (Save-OpOfficeSource), et la version obtenue relevée ; une version absente
        du manifeste y est inscrite (élément office-source, SHA-256 de chaque fichier) à la place de la précédente ;
        une source en échec compte comme une erreur. Enfin, la purge (Invoke-OpDepotPurge) retire ce que la rétention
        ne garde plus et liste les fichiers orphelins sans les supprimer ; son résultat est dans la propriété Purge.
        Renvoie un objet : ListOnly, Items (éléments de Get-OpDepotPlan), DownloadBytes (fichiers à télécharger,
        comptés une fois), DownloadCount, UnknownSizeCount, FreeBytes (volume du dépôt, $null si illisible),
        EnoughSpace, ErrorCount (liens refusés, puis éléments non inscrits), NewItems (éléments ajoutés au manifeste
        par ce lancement, résumé des nouveautés), Odt (plan de Get-OpOdtPlan, $null sans source Office), OdtUpdated,
        Office (un résultat de Save-OpOfficeSource par source, ou Id, Channel et Error en cas d'échec).

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
        # ODT : utile seulement si une source Office est configurée ; une erreur est portée par le plan.
        $odt = $null
        if (@($configuration.OfficeSources.sources).Count -gt 0) { $odt = Get-OpOdtPlan -Configuration $configuration -Root $Root }
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
    if ($odt) {
        if ($odt.Error) {
            $errorCount++
            Write-OpLog -Level ERROR -Message "Dépôt, ODT refusé. $($odt.Error)"
        } elseif ($odt.UpToDate) {
            Write-OpLog "Dépôt, ODT à jour : setup.exe $($odt.InstalledVersion) (dernière version $($odt.Version))."
        } else {
            Write-OpLog "Dépôt, ODT $($odt.Version) à télécharger ($(@($odt.Hosts) -join ' -> '))."
            $seen[$odt.Url] = $true
            if ($null -eq $odt.SizeBytes) { $unknown++ } else { $bytes += $odt.SizeBytes }
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
        Odt              = $odt
        OdtUpdated       = $false
        Office           = @()
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
    # Avancement affiché dans la console de la CLI (Write-OpProgress) : un fichier partagé n'est compté qu'une fois.
    $toFetch = @($items | ForEach-Object { $_.Files } | Where-Object { -not $_.Error -and -not $_.InDepot } | ForEach-Object { $_.Url } | Sort-Object -Unique)
    $fileIndex = 0
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
                    $fileIndex++
                    Write-OpProgress ('Fichier {0}/{1} : {2} ({3})' -f $fileIndex, $toFetch.Count, $f.FileName, (Format-OpSize $f.SizeBytes))
                    $fileStart = Get-Date
                    $downloaded[$f.Url] = Save-OpDepotFile -Item $item -File $f -Configuration $configuration -Root $Root -Confirm:$false
                    Write-OpProgress ('  terminé et contrôlé en {0:N0} s.' -f ((Get-Date) - $fileStart).TotalSeconds)
                } catch {
                    $downloaded[$f.Url] = $_.Exception.Message
                    Write-OpProgress "  échec : $($_.Exception.Message)"
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

    if ($odt -and -not $odt.Error -and -not $odt.UpToDate) {
        try {
            Write-OpProgress "ODT $($odt.Version) : téléchargement et extraction."
            Save-OpOdt -Plan $odt -Configuration $configuration -Root $Root -Confirm:$false | Out-Null
            $result.OdtUpdated = $true
        } catch {
            $errorCount++
            Write-OpLog -Level ERROR -Message "Dépôt, ODT non mis à jour. $($_.Exception.Message)"
        }
    }

    # Sources Office : setup.exe /download par source, avec l'ODT de tools\odt, même ancien si sa mise à jour a échoué.
    $office = New-Object System.Collections.Generic.List[object]
    if ($odt) {
        foreach ($src in @(Get-OpOfficeDownloadXml -Configuration $configuration -Root $Root)) {
            try {
                Write-OpProgress "Source Office $($src.Id) ($($src.Channel)) : setup.exe /download en cours ; l'ODT n'indique pas sa progression (plusieurs Go, souvent 10 à 30 min)."
                $saved = Save-OpOfficeSource -Source $src -SetupPath $odt.SetupPath -Root $Root -Confirm:$false
                $version = $null
                if ($saved.PSObject.Properties['Version']) { $version = $saved.Version }
                Write-OpProgress "  terminé : version $version."
                # Élément office-source : remplace celui de la version précédente de la même source (7.2).
                $folder = @($configuration.OfficeSources.sources | Where-Object { $_.id -eq $src.Id })[0].folder
                if (-not @($manifest.items | Where-Object { $_.id -eq "office-$($src.Id)-$($saved.Version)" })) {
                    $manifestItem = ConvertTo-OpOfficeManifestItem -Result $saved -Folder $folder -Depot (Get-OpPath -Name Depot -Root $Root)
                    $manifest.items = @(@($manifest.items | Where-Object { -not ($_.category -eq 'office-source' -and $_.folder -eq $folder) }) + $manifestItem)
                    Save-OpManifest -Manifest $manifest -Path $manifestPath -ToolVersion $toolVersion -Confirm:$false
                    $new.Add($manifestItem)
                    Write-OpLog "Dépôt : nouveauté inscrite au manifeste, $($manifestItem.id) ($(@($manifestItem.files).Count) fichier(s))."
                }
                $office.Add($saved)
            } catch {
                $errorCount++
                Write-OpLog -Level ERROR -Message "Dépôt, source Office $($src.Id) non mise à jour. $($_.Exception.Message)"
                $office.Add([pscustomobject]@{ Id = $src.Id; Channel = $src.Channel; Version = $null; Updated = $false; Error = $_.Exception.Message })
            }
        }
    }
    $result.Office = $office.ToArray()

    $result.ErrorCount = $errorCount
    $result.NewItems = $new.ToArray()
    Write-OpLog ("Mise à jour du dépôt terminée : {0} nouveauté(s), {1} erreur(s)." -f $new.Count, $errorCount)

    # Purge après la vérification du mois nouveau (7.3) : un mois qui a échoué n'est pas au manifeste, l'ancien reste
    # donc parmi les plus récents. Les orphelins sont seulement listés.
    $result | Add-Member -NotePropertyName Purge -NotePropertyValue (Invoke-OpDepotPurge -Root $Root -Confirm:$false)
    $result
}
