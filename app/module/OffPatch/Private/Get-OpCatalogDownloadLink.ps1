function Get-OpCatalogDownloadLink {
    <#
    .SYNOPSIS
        Résout les liens de téléchargement d'une entrée du Microsoft Update Catalog (DownloadDialog.aspx).

    .DESCRIPTION
        Lecture seule : requête POST de la fenêtre de téléchargement par Invoke-OpWebRequest (nouvelles tentatives
        sur une erreur passagère), puis analyse par ConvertFrom-OpCatalogDownloadDialog. Une fenêtre non reconnue
        lève une erreur qui donne l'URL, l'identifiant de l'entrée et un extrait de la page.
        Renvoie un objet par fichier (Url, FileName, Sha1).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F\-]{36}$')][string]$UpdateId
    )

    $uri = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'
    $payload = '[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]'
    $html = Invoke-OpWebRequest -Uri $uri -Method Post -Body ('updateIDs=' + [uri]::EscapeDataString($payload)) -ContentType 'application/x-www-form-urlencoded'
    try {
        ConvertFrom-OpCatalogDownloadDialog -Html $html
    } catch {
        $text = ($html -replace '(?s)<script.*?</script>', '' -replace '(?s)<style.*?</style>', '' -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
        if ($text.Length -gt 300) { $text = $text.Substring(0, 300) }
        throw ("{0} URL {1}, entrée {2}. Extrait de la page : {3}" -f $_.Exception.Message, $uri, $UpdateId, $text)
    }
}
