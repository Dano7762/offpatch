function Find-OpCatalogUpdate {
    <#
    .SYNOPSIS
        Interroge le Microsoft Update Catalog et renvoie toutes les lignes de résultat, page après page.

    .DESCRIPTION
        Lecture seule. Demande Search.aspx?q=<recherche>&p=<index> (index de page à partir de 0, comme le
        script de pagination du site) tant que la page reçue est pleine et que le compteur « page N of M »
        annonce une page suivante (R-11). Les lignes sont dédoublonnées par identifiant de mise à jour.
        Au-delà de MaxPages pages, la recherche échoue : un résultat tronqué n'est jamais renvoyé en silence.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Query,
        [ValidateRange(1, 100)][int]$MaxPages = 10
    )

    $items = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $pageIndex = 0
    $hasNextPage = $true
    while ($hasNextPage) {
        if ($pageIndex -ge $MaxPages) {
            throw "Recherche « $Query » : plus de $MaxPages page(s) de résultats ; résultat tronqué refusé, préciser la recherche."
        }
        $uri = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($Query)
        if ($pageIndex -gt 0) { $uri += '&p=' + $pageIndex }
        $html = (Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop).Content
        $page = ConvertFrom-OpCatalogSearchPage -Html $html
        foreach ($item in $page.Items) {
            if (-not $seen.ContainsKey($item.UpdateId)) {
                $seen[$item.UpdateId] = $true
                $items.Add($item)
            }
        }
        $hasNextPage = $page.HasNextPage
        $pageIndex++
    }
    $items.ToArray()
}
