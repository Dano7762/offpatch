function Invoke-OpHeadRequest {
    <#
    .SYNOPSIS
        Envoie une requête HEAD sans suivre les redirections et renvoie le code HTTP et l'en-tête Location.

    .DESCRIPTION
        Lecture seule, aucun téléchargement de contenu. Séparée de Resolve-OpDownloadUrl pour pouvoir être
        remplacée par un mock dans les tests Pester. Même politique de nouvelles tentatives qu'Invoke-OpWebRequest :
        MaxAttempts tentatives au plus, attente de DelaySeconds × numéro de tentative, seulement sans réponse
        (réseau, délai) ou sur HTTP 408, 429 ou 5xx ; le dernier code reçu est alors renvoyé, ou l'erreur réseau
        relancée avec l'URL.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [ValidateRange(1, 10)][int]$MaxAttempts = 3,
        [ValidateRange(0, 300)][int]$DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $request.AllowAutoRedirect = $false
        $request.Timeout = 60000
        $response = $null
        try {
            try {
                $response = $request.GetResponse()
            } catch [System.Net.WebException] {
                # Un code 3xx ou 4xx arrive ici : on garde la réponse ; sans réponse (réseau), nouvelle tentative.
                $response = $_.Exception.Response
                if (-not $response) {
                    if ($attempt -ge $MaxAttempts) { throw "Requête HEAD sans réponse après $attempt tentative(s), URL $Url : $($_.Exception.Message)" }
                    Start-Sleep -Seconds ($DelaySeconds * $attempt)
                    continue
                }
            }
            $statusCode = [int]$response.StatusCode
            $transient = $statusCode -eq 408 -or $statusCode -eq 429 -or $statusCode -ge 500
            if ($transient -and $attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds ($DelaySeconds * $attempt)
                continue
            }
            return [pscustomobject]@{
                StatusCode = $statusCode
                Location   = $response.Headers['Location']
            }
        } finally {
            if ($response) { $response.Close() }
        }
    }
}
