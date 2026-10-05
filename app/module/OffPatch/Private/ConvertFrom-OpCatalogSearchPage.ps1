function ConvertFrom-OpCatalogSearchPage {
    <#
    .SYNOPSIS
        Extrait les lignes de résultat d'une page de recherche du Microsoft Update Catalog (Search.aspx).

    .DESCRIPTION
        Fonction pure, sans accès réseau : elle reçoit le HTML de la page et renvoie un objet par ligne
        (identifiant de mise à jour, titre, produits, classification, date, taille). Elle signale aussi
        une page « aucun résultat » et lit le compteur « page N of M » : HasNextPage indique qu'une page
        suivante existe (page pleine de 25 lignes et compteur non atteint), pour la pagination (R-11).
        Une structure de page inattendue lève une erreur explicite plutôt que de renvoyer une liste vide.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Html
    )

    $noResults = $Html -match 'id="ctl00_catalogBody_noResultText"'
    $rows = [regex]::Matches($Html, '(?s)<tr id="([0-9a-f\-]{36})_R\d+"[^>]*>(.*?)</tr>')
    if (-not $noResults -and $rows.Count -eq 0) {
        throw 'Page du catalogue non reconnue : ni ligne de résultat, ni message « aucun résultat ».'
    }

    $items = foreach ($row in $rows) {
        $id = $row.Groups[1].Value
        $cells = [regex]::Matches($row.Groups[2].Value, '(?s)<td[^>]*>(.*?)</td>')
        if ($cells.Count -lt 7) { throw "Ligne de résultat $id incomplète : $($cells.Count) cellules." }
        $text = @(foreach ($c in $cells) {
                ($c.Groups[1].Value -replace '(?s)<span class="noDisplay"[^>]*>.*?</span>', '' -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '\s+', ' ').Trim()
            })
        $sizeBytes = $null
        $original = [regex]::Match($row.Groups[2].Value, "id=""$id`_originalSize"">\s*(\d+)\s*<")
        if ($original.Success) { $sizeBytes = [int64]$original.Groups[1].Value }
        $date = $null
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($text[4], 'M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { $date = $parsed }
        [pscustomobject]@{
            UpdateId       = $id
            Title          = $text[1]
            Products       = $text[2]
            Classification = $text[3]
            LastUpdated    = $date
            SizeText       = $text[6]
            SizeBytes      = $sizeBytes
        }
    }

    # Compteur du catalogue : « 26 - 50 of 76 (page 2 of 4) ». Absent sur la page « aucun résultat ».
    $pageNumber = $null
    $pageCount = $null
    $totalCount = $null
    $counter = [regex]::Match($Html, 'id="ctl00_catalogBody_searchDuration">\s*\d+\s*-\s*\d+\s+of\s+(\d+)\s+\(page\s+(\d+)\s+of\s+(\d+)\)')
    if ($counter.Success) {
        $totalCount = [int]$counter.Groups[1].Value
        $pageNumber = [int]$counter.Groups[2].Value
        $pageCount = [int]$counter.Groups[3].Value
    }
    $hasNextPage = ($rows.Count -ge 25)
    if ($hasNextPage -and $counter.Success) { $hasNextPage = ($pageNumber -lt $pageCount) }

    [pscustomobject]@{
        NoResults   = $noResults
        PageNumber  = $pageNumber
        PageCount   = $pageCount
        TotalCount  = $totalCount
        HasNextPage = $hasNextPage
        Items       = @($items)
    }
}
