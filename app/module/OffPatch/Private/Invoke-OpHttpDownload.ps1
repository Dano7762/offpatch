function Invoke-OpHttpDownload {
    <#
    .SYNOPSIS
        Télécharge un fichier par HttpClient, en flux, avec reprise d'un fichier partiel (repli de BITS).

    .DESCRIPTION
        Repli quand BITS n'est pas disponible (cahier des charges 7.1, R-16). Les octets arrivent dans
        « <Destination>.part » ; s'il existe déjà (lancement interrompu), seule la suite est demandée par un en-tête
        Range : réponse 206, ajout à la fin ; réponse 200 (serveur sans Range), téléchargement repris de zéro.
        Redirections refusées (AllowAutoRedirect à faux) : l'URL reçue est déjà l'URL finale. Tout autre code HTTP
        lève une erreur et garde le fichier partiel pour la reprise. Fichier complet : « .part » renommé en Destination.
        ReadTimeoutSeconds borne l'attente de la réponse et, quand le flux le permet, chaque lecture : une connexion
        muette est abandonnée, le fichier partiel reste pour la reprise.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [ValidateRange(1, 3600)][int]$ReadTimeoutSeconds = 120
    )

    if (-not $PSCmdlet.ShouldProcess($Destination, "Téléchargement HttpClient de $Url")) { return }
    Add-Type -AssemblyName System.Net.Http
    $part = $Destination + '.part'
    $existing = [long]0
    if (Test-Path -LiteralPath $part -PathType Leaf) { $existing = (Get-Item -LiteralPath $part).Length }

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($ReadTimeoutSeconds)
    $response = $null
    $stream = $null
    $file = $null
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Url)
        if ($existing -gt 0) { $request.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue($existing, $null) }
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
        $resumed = $false
        if ($status -eq 206 -and $existing -gt 0) {
            $mode = [System.IO.FileMode]::Append
            $resumed = $true
        } elseif ($status -eq 200) {
            $mode = [System.IO.FileMode]::Create
            if ($existing -gt 0) { Write-OpLog -Level WARN -Message "HttpClient : le serveur ignore la reprise (HTTP 200), téléchargement repris de zéro : $Url" }
        } elseif ($status -ge 300 -and $status -lt 400) {
            throw "Téléchargement refusé : redirection HTTP $status vers « $($response.Headers.Location) » non contrôlée, $Url"
        } else {
            throw "Téléchargement HttpClient en échec (HTTP $status), $Url"
        }

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        if ($stream.CanTimeout) { $stream.ReadTimeout = $ReadTimeoutSeconds * 1000 }
        $file = New-Object System.IO.FileStream($part, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (1MB)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $file.Write($buffer, 0, $read) }
        $file.Close()
        $file = $null
    } finally {
        if ($file) { $file.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
    }

    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
    Move-Item -LiteralPath $part -Destination $Destination
    [pscustomobject]@{ Path = $Destination; Engine = 'HttpClient'; Resumed = $resumed; SizeBytes = (Get-Item -LiteralPath $Destination).Length }
}
