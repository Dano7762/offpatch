function Invoke-OpHeadRequest {
    <#
    .SYNOPSIS
        Envoie une requête HEAD sans suivre les redirections et renvoie le code HTTP et l'en-tête Location.

    .DESCRIPTION
        Lecture seule, aucun téléchargement de contenu. Séparée de Resolve-OpDownloadUrl pour pouvoir être
        remplacée par un mock dans les tests Pester.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url
    )

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 60000
    $response = $null
    try {
        try {
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            # Un code 3xx ou 4xx arrive ici : on garde la réponse, sinon (réseau) on relance l'erreur.
            $response = $_.Exception.Response
            if (-not $response) { throw }
        }
        [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Location   = $response.Headers['Location']
        }
    } finally {
        if ($response) { $response.Close() }
    }
}
