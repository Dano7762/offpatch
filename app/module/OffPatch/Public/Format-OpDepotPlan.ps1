function Format-OpDepotPlan {
    <#
    .SYNOPSIS
        Met en forme, en lignes de texte, le résultat d'Invoke-OpDepotUpdate, avec ou sans -ListOnly (affichage de la CLI).

    .DESCRIPTION
        Fonction pure. Une section par cible, une ligne par fichier : état (à télécharger, au dépôt, refusé),
        catégorie, KB, UBR ou version, nom du fichier et taille ; puis un résumé : nombre de fichiers et taille à
        télécharger, espace libre du volume du dépôt, manque d'espace éventuel. Les tailles sont en Mo et Go
        (base 1024), au format français. Après un téléchargement (sans -ListOnly), résumé des nouveautés : chaque
        élément ajouté au manifeste, avec sa catégorie, son KB, son UBR ou sa version et sa taille.

    .PARAMETER Result
        Objet renvoyé par Invoke-OpDepotUpdate.

    .EXAMPLE
        Format-OpDepotPlan -Result (Invoke-OpDepotUpdate -ListOnly)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Result
    )

    $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    function Format-Size($Bytes) {
        if ($null -eq $Bytes) { return 'taille inconnue' }
        if ($Bytes -ge 1GB) { return ([double]$Bytes / 1GB).ToString('N2', $fr) + ' Go' }
        ([double]$Bytes / 1MB).ToString('N1', $fr) + ' Mo'
    }

    foreach ($group in @($Result.Items | Group-Object -Property Target)) {
        "Cible $($group.Name)"
        foreach ($item in $group.Group) {
            $parts = @()
            if ($item.Kb) { $parts += $item.Kb }
            if ($null -ne $item.ResultingUbr) { $parts += "UBR $($item.ResultingUbr)" }
            if ($null -ne $item.Version) { $parts += "version $($item.Version)" }
            $detail = $parts -join ', '
            foreach ($f in $item.Files) {
                $state = 'à télécharger'
                if ($f.Error) { $state = 'REFUSÉ' } elseif ($f.InDepot) { $state = 'au dépôt' }
                $line = '  [{0}] {1} ({2}) : {3}' -f $state, $item.Category, $detail, $f.FileName
                if (-not $f.InDepot -and -not $f.Error) { $line += ', ' + (Format-Size $f.SizeBytes) }
                $line
                if ($f.Error) { '      ' + $f.Error }
            }
            foreach ($w in @($item.Warnings)) { '      Avertissement : ' + $w }
        }
    }
    $summary = 'À télécharger : {0} fichier(s), {1}' -f $Result.DownloadCount, (Format-Size $Result.DownloadBytes)
    if ($Result.UnknownSizeCount -gt 0) { $summary += " (taille inconnue pour $($Result.UnknownSizeCount) fichier(s))" }
    $summary
    if ($null -eq $Result.FreeBytes) { 'Espace libre du volume du dépôt : illisible.' }
    else {
        'Espace libre du volume du dépôt : ' + (Format-Size $Result.FreeBytes) + '.'
        if ($Result.EnoughSpace -eq $false) { 'Espace insuffisant : il manque ' + (Format-Size ($Result.DownloadBytes - $Result.FreeBytes)) + ', la mise à jour s''arrêterait avant tout téléchargement.' }
    }
    $listOnly = ($null -eq $Result.PSObject.Properties['ListOnly']) -or $Result.ListOnly
    if ($listOnly) {
        if ($Result.ErrorCount -gt 0) { "$($Result.ErrorCount) lien(s) refusé(s) ou inaccessible(s) : voir ci-dessus." }
        'Aucun fichier téléchargé (-ListOnly). Sources Office : pas encore prises en charge.'
        return
    }

    # Résumé des nouveautés du mois (7.1) : éléments ajoutés au manifeste par ce lancement.
    $new = @($Result.NewItems)
    if ($new.Count -eq 0) { 'Aucune nouveauté : le dépôt était déjà à jour.' }
    else {
        "Nouveautés inscrites au manifeste : $($new.Count)"
        foreach ($n in $new) {
            $size = [long]0
            foreach ($f in @($n.files)) { $size += [long]$f.size }
            $parts = @()
            if ($null -ne $n.PSObject.Properties['kb']) { $parts += $n.kb }
            if ($null -ne $n.PSObject.Properties['resultingUbr']) { $parts += "UBR $($n.resultingUbr)" }
            if ($null -ne $n.PSObject.Properties['version']) { $parts += "version $($n.version)" }
            '  + {0} : {1} ({2}), {3}' -f $n.id, $n.category, ($parts -join ', '), (Format-Size $size)
        }
    }
    if ($Result.ErrorCount -gt 0) { "$($Result.ErrorCount) erreur(s) : liens refusés ou éléments non inscrits, voir le journal." }
    'Sources Office : pas encore prises en charge.'
}
