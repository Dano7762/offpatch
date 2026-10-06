function Resolve-OpDownloadUrl {
    <#
    .SYNOPSIS
        Résout la chaîne de redirections d'un lien de téléchargement et contrôle chaque hôte (allowedDomains).

    .DESCRIPTION
        Lecture seule, avant tout téléchargement (cahier des charges 6.1, 7.1, 11 ; R-13). Les redirections sont
        suivies une à une, sans redirection automatique :
          - un lien http est réécrit en https sur le même hôte ; rien n'est jamais demandé en http ;
          - l'hôte de chaque étape doit figurer tel quel dans AllowedDomain (nom exact, sans joker ni suffixe) ;
          - au-delà de MaxRedirects redirections, ou sur un code final autre que 2xx, la résolution échoue.
        Hôte inconnu : erreur qui donne l'hôte, l'URL complète et la ligne exacte à ajouter à allowedDomains.
        Renvoie l'URL finale, à télécharger telle quelle, et la liste des hôtes traversés.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedDomain,
        [ValidateRange(0, 20)][int]$MaxRedirects = 10
    )

    $allowed = @($AllowedDomain | ForEach-Object { $_.ToLowerInvariant() })
    $hosts = New-Object System.Collections.Generic.List[string]
    $current = $Url
    for ($step = 0; $step -le $MaxRedirects; $step++) {
        $uri = [uri]$current
        if ($uri.Scheme -eq 'http') {
            $builder = New-Object System.UriBuilder($uri)
            $builder.Scheme = 'https'
            $builder.Port = -1
            $uri = $builder.Uri
        } elseif ($uri.Scheme -ne 'https') {
            throw "Lien refusé, schéma $($uri.Scheme) non autorisé : $current"
        }
        $hostName = $uri.Host.ToLowerInvariant()
        if ($allowed -notcontains $hostName) {
            throw ("Hôte non autorisé : {0}. URL : {1}. Si l'hôte est légitime (domaine Microsoft vérifié), ajouter à allowedDomains dans config/settings.json la ligne : `"{0}`"," -f $hostName, $uri.AbsoluteUri)
        }
        $hosts.Add($hostName)

        $response = Invoke-OpHeadRequest -Url $uri.AbsoluteUri
        if ($response.StatusCode -ge 300 -and $response.StatusCode -lt 400) {
            if (-not $response.Location) { throw "Redirection $($response.StatusCode) sans en-tête Location : $($uri.AbsoluteUri)" }
            $current = (New-Object System.Uri($uri, [string]$response.Location)).AbsoluteUri
            continue
        }
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw "Lien inaccessible (HTTP $($response.StatusCode)) : $($uri.AbsoluteUri)"
        }
        return [pscustomobject]@{
            Url   = $uri.AbsoluteUri
            Hosts = $hosts.ToArray()
        }
    }
    throw "Plus de $MaxRedirects redirections à partir de $Url : lien refusé."
}
