function Confirm-OpDownloadIntegrity {
    <#
    .SYNOPSIS
        Contrôle un fichier reçu dans le dossier temporaire du dépôt et calcule son SHA-256.

    .DESCRIPTION
        Étape 5 de la mise à jour du dépôt (cahier des charges 7.1 et 11, R-10), pour les fichiers Windows, .NET et
        Defender, tous signés :
          - signature Authenticode jugée par Test-OpFileSignature (Valid, O=Microsoft Corporation, racine de
            TrustedRootThumbprint) ;
          - SHA-1 et SHA-256 calculés en une seule lecture du fichier (une cumulative fait plus de 4 Go) ;
          - avec ExpectedSha1 (empreinte lue dans le nom du fichier ou dans pinned-items.json), SHA-1 comparé.
        Au moindre écart, le fichier est supprimé et une erreur explicite est levée : il sera retéléchargé au
        lancement suivant. Renvoie Path, Sha256 et Sha1 (minuscules), Signer, RootThumbprint.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$TrustedRootThumbprint,
        [string]$ExpectedSha1
    )

    $name = [System.IO.Path]::GetFileName($Path)
    $reason = $null
    $signature = Test-OpFileSignature -Path $Path -TrustedRootThumbprint $TrustedRootThumbprint
    if (-not $signature.IsTrusted) {
        $reason = $signature.Reason
    } else {
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $buffer = New-Object byte[] (1MB)
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                [void]$sha1.TransformBlock($buffer, 0, $read, $null, 0)
                [void]$sha256.TransformBlock($buffer, 0, $read, $null, 0)
            }
            [void]$sha1.TransformFinalBlock($buffer, 0, 0)
            [void]$sha256.TransformFinalBlock($buffer, 0, 0)
            $sha1Hex = -join ($sha1.Hash | ForEach-Object { $_.ToString('x2') })
            $sha256Hex = -join ($sha256.Hash | ForEach-Object { $_.ToString('x2') })
        } finally {
            $stream.Dispose()
            $sha1.Dispose()
            $sha256.Dispose()
        }
        if ($ExpectedSha1 -and $sha1Hex -ne $ExpectedSha1.ToLowerInvariant()) {
            $reason = "SHA-1 $sha1Hex différent de l'empreinte publiée $($ExpectedSha1.ToLowerInvariant())."
        }
    }

    if ($reason) {
        if ($PSCmdlet.ShouldProcess($Path, 'Suppression du fichier refusé')) { Remove-Item -LiteralPath $Path -Force }
        Write-OpLog -Level ERROR -Message "Intégrité : $name refusé. $reason Fichier supprimé."
        throw "Fichier refusé, $name : $reason"
    }
    Write-OpLog "Intégrité : $name conforme (signataire $($signature.Signer), racine $($signature.RootThumbprint)), SHA-256 $sha256Hex."
    [pscustomobject]@{
        Path           = $Path
        Sha256         = $sha256Hex
        Sha1           = $sha1Hex
        Signer         = $signature.Signer
        RootThumbprint = $signature.RootThumbprint
    }
}
