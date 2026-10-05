function ConvertFrom-OpCatalogDownloadDialog {
    <#
    .SYNOPSIS
        Extrait les liens de fichiers de la fenêtre de téléchargement du Microsoft Update Catalog (DownloadDialog.aspx).

    .DESCRIPTION
        Fonction pure, sans accès réseau : elle reçoit le HTML de la fenêtre et renvoie un objet par fichier
        (lien, nom, SHA-1 lu dans le nom quand il y figure). Une fenêtre sans aucun lien lève une erreur explicite.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Html
    )

    $links = [regex]::Matches($Html, "\.url = '(https?://[^']+)'")
    if ($links.Count -eq 0) {
        throw 'Fenêtre de téléchargement du catalogue non reconnue : aucun lien de fichier.'
    }
    $seen = @{}
    foreach ($m in $links) {
        $url = $m.Groups[1].Value
        if ($seen.ContainsKey($url)) { continue }
        $seen[$url] = $true
        $name = ([uri]$url).Segments[-1]
        $sha1 = $null
        $fromName = [regex]::Match($name, '_([0-9a-fA-F]{40})\.\w+$')
        if ($fromName.Success) { $sha1 = $fromName.Groups[1].Value.ToLowerInvariant() }
        [pscustomobject]@{
            Url      = $url
            FileName = $name
            Sha1     = $sha1
        }
    }
}
