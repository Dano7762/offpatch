function Get-OpCatalogSelection {
    <#
    .SYNOPSIS
        Interroge le catalogue pour une cible et renvoie l'élément retenu pour chaque catégorie de catalog-queries.json.

    .DESCRIPTION
        Lecture seule (cahier des charges 6.2 et 7.1, étape 2). Pour chaque entrée de la cible : {month} est remplacé
        par chacun des monthsToSearch derniers mois au format AAAA-MM (mois courant d'abord), chaque recherche passe
        par Find-OpCatalogUpdate (pagination comprise), les lignes sont fusionnées par identifiant de mise à jour,
        puis Select-OpCatalogUpdate applique les motifs et la règle de sélection. Pour la règle
        highestUbrFromReleaseInformation, la page release-information (settings.json, downloadPages) est lue une
        seule fois ; si elle est inaccessible ou non reconnue, la sélection se replie sur le mois du titre, avec un
        avertissement. Chaque avertissement est écrit dans le journal.
        Renvoie un objet par entrée de la cible (celui de Select-OpCatalogUpdate, avec Target et Queries).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,
        [datetime]$Now = (Get-Date)
    )

    $queries = $Configuration.CatalogQueries
    if ($null -eq $queries.targets.PSObject.Properties[$Target]) {
        throw "catalog-queries.json : aucune recherche pour la cible $Target."
    }
    $months = @(for ($i = 0; $i -lt [int]$queries.monthsToSearch; $i++) {
            $Now.AddMonths(-$i).ToString('yyyy-MM', [Globalization.CultureInfo]::InvariantCulture)
        })

    $releaseInformation = @{}
    foreach ($entry in @($queries.targets.$Target)) {
        $label = "$Target / $($entry.category)"
        $texts = New-Object System.Collections.Generic.List[string]
        foreach ($search in @($entry.searches)) {
            if ($search -like '*{month}*') { foreach ($m in $months) { $texts.Add($search.Replace('{month}', $m)) } }
            else { $texts.Add($search) }
        }
        $items = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        foreach ($text in ($texts | Select-Object -Unique)) {
            $found = @(Find-OpCatalogUpdate -Query $text)
            Write-OpLog -Level DEBUG -Message "Catalogue, $label : « $text », $($found.Count) ligne(s)."
            foreach ($f in $found) {
                if (-not $seen.ContainsKey($f.UpdateId)) { $seen[$f.UpdateId] = $true ; $items.Add($f) }
            }
        }

        $map = $null
        if ($entry.pick -eq 'highestUbrFromReleaseInformation') {
            $uri = $Configuration.Settings.downloadPages.windows10ReleaseInformation
            $build = [int]$entry.releaseInformationBuild
            $key = "$uri|$build"
            if (-not $releaseInformation.ContainsKey($key)) {
                try {
                    $releaseInformation[$key] = Get-OpWindows10ReleaseInfo -Uri $uri -BaseBuild $build
                } catch {
                    Write-OpLog -Level WARN -Message "Catalogue, $label : page release-information illisible, sélection par le mois du titre. $($_.Exception.Message)"
                    $releaseInformation[$key] = $null
                }
            }
            $map = $releaseInformation[$key]
        }

        $selection = Select-OpCatalogUpdate -Item $items.ToArray() -Entry $entry -ReleaseInformation $map
        foreach ($w in $selection.Warnings) { Write-OpLog -Level WARN -Message "Catalogue, $Target : $w" }
        if ($selection.Kb) {
            $detail = $selection.Kb
            if ($null -ne $selection.ResultingUbr) { $detail += ", UBR $($selection.ResultingUbr)" }
            if ($null -ne $selection.Version) { $detail += ", version $($selection.Version)" }
            Write-OpLog -Message "Catalogue, $label : $detail retenu (« $($selection.Title) »)."
        }
        $selection | Add-Member -NotePropertyName Target -NotePropertyValue $Target
        $selection | Add-Member -NotePropertyName Queries -NotePropertyValue $texts.ToArray()
        $selection
    }
}
