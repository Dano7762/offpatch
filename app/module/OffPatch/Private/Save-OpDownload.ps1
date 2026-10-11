function Save-OpDownload {
    <#
    .SYNOPSIS
        Télécharge un fichier dans le dossier temporaire du dépôt : BITS d'abord, HttpClient en repli.

    .DESCRIPTION
        Étape 4 de la mise à jour du dépôt (cahier des charges 7.1, R-16). L'URL doit être l'URL finale, déjà résolue
        et contrôlée par Resolve-OpDownloadUrl : https seulement, aucune redirection suivie pendant le transfert.
        Engine Auto : BITS (Invoke-OpBitsDownload), puis HttpClient (Invoke-OpHttpDownload) si BITS est indisponible
        (module absent, travail non créé ou bloqué en file d'attente) ; une autre erreur de BITS n'entraîne pas de repli.
        Un téléchargement interrompu reprend au lancement suivant : travail BITS conservé ou fichier « .part ».
        Fichier déjà présent à Destination (lancement précédent arrêté juste après le transfert) : gardé tel quel.
        Avec ExpectedSize, un fichier d'une autre taille est supprimé et une erreur est levée.
        Renvoie Path, Engine (BITS, HttpClient ou Existing), Resumed, SizeBytes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [System.Nullable[long]]$ExpectedSize,
        [ValidateSet('Auto', 'Bits', 'HttpClient')][string]$Engine = 'Auto',
        [ValidateRange(1, 3600)][int]$QueuedSeconds = 60,
        [ValidateRange(1, 86400)][int]$StallSeconds = 300
    )

    $uri = $null
    if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "Téléchargement refusé, lien non https : $Url"
    }
    if (-not $PSCmdlet.ShouldProcess($Destination, "Téléchargement de $Url")) { return }
    $folder = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }

    $started = Get-Date
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $result = [pscustomobject]@{ Path = $Destination; Engine = 'Existing'; Resumed = $false; SizeBytes = (Get-Item -LiteralPath $Destination).Length }
        Write-OpLog "Téléchargement : $([System.IO.Path]::GetFileName($Destination)) déjà présent dans le dossier temporaire."
    } else {
        Write-OpLog "Téléchargement de $Url"
        $result = $null
        if ($Engine -ne 'HttpClient') {
            try {
                $result = Invoke-OpBitsDownload -Url $Url -Destination $Destination -QueuedSeconds $QueuedSeconds -StallSeconds $StallSeconds -Confirm:$false
            } catch [System.NotSupportedException] {
                if ($Engine -eq 'Bits') { throw }
                Write-OpLog -Level WARN -Message "$($_.Exception.Message) Repli sur HttpClient."
            }
        }
        if (-not $result) { $result = Invoke-OpHttpDownload -Url $Url -Destination $Destination -Confirm:$false }
    }

    $size = (Get-Item -LiteralPath $Destination).Length
    $result.SizeBytes = $size
    if ($null -ne $ExpectedSize -and $size -ne $ExpectedSize) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Téléchargement incomplet ou altéré : $size octet(s) reçus, $ExpectedSize attendus, $Url. Fichier supprimé."
    }
    Write-OpLog ("Téléchargé ({0}{1}) : {2}, {3:N0} octets en {4:N0} s." -f $result.Engine, $(if ($result.Resumed) { ', repris' } else { '' }), [System.IO.Path]::GetFileName($Destination), $size, ((Get-Date) - $started).TotalSeconds)
    $result
}
