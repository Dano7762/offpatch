function Invoke-OpWebRequest {
    <#
    .SYNOPSIS
        Requête web en lecture (page ou formulaire), avec la politique de nouvelles tentatives de l'outil.

    .DESCRIPTION
        Lecture seule, pour les pages (catalogue, page de l'ODT) ; les fichiers passent par le téléchargement BITS.
        Politique : MaxAttempts tentatives au plus, attente de DelaySeconds × numéro de tentative entre deux essais,
        seulement sur une erreur passagère : pas de réponse (réseau, délai), HTTP 408, 429 ou 5xx. Une autre erreur
        HTTP (404…) échoue tout de suite. L'erreur finale donne le code HTTP, l'URL et un extrait de la réponse reçue.
        Renvoie le contenu de la réponse (chaîne).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('Get', 'Post')][string]$Method = 'Get',
        [string]$Body,
        [string]$ContentType,
        [ValidateRange(1, 10)][int]$MaxAttempts = 3,
        [ValidateRange(0, 300)][int]$DelaySeconds = 10
    )

    $parameters = @{ Uri = $Uri; Method = $Method; UseBasicParsing = $true; ErrorAction = 'Stop'; TimeoutSec = 120 }
    if ($Body) { $parameters.Body = $Body }
    if ($ContentType) { $parameters.ContentType = $ContentType }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return (Invoke-WebRequest @parameters).Content
        } catch {
            $statusCode = $null
            $excerpt = ''
            $response = $null
            if ($_.Exception.PSObject.Properties['Response']) { $response = $_.Exception.Response }
            if ($response) {
                $statusCode = [int]$response.StatusCode
                try {
                    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                    $excerpt = $reader.ReadToEnd()
                    $reader.Dispose()
                } catch {
                    $excerpt = ''
                }
            }
            $transient = (-not $statusCode) -or $statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500
            if (-not $transient -or $attempt -ge $MaxAttempts) {
                $text = ($excerpt -replace '(?s)<script.*?</script>', '' -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
                if ($text.Length -gt 300) { $text = $text.Substring(0, 300) }
                $code = 'aucune réponse'
                if ($statusCode) { $code = "HTTP $statusCode" }
                throw ("Requête en échec après {0} tentative(s) : {1}, URL {2}. {3} Extrait de la réponse : {4}" -f $attempt, $code, $Uri, $_.Exception.Message, $text)
            }
            Start-Sleep -Seconds ($DelaySeconds * $attempt)
        }
    }
}
