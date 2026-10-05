function Test-OpFileSignature {
    <#
    .SYNOPSIS
        Vérifie la signature Authenticode d'un fichier téléchargé selon les critères du cahier des charges (7.1, 11).

    .DESCRIPTION
        Lecture seule, côté dépôt. Le fichier est accepté si :
          - Get-AuthenticodeSignature renvoie Status = Valid ;
          - le certificat du signataire porte l'organisation O=Microsoft Corporation ;
          - la chaîne remonte à une racine autosignée dont l'empreinte figure dans TrustedRootThumbprint
            (integrity.trustedRootThumbprints de settings.json).
        La chaîne est reconstruite sans contrôle de date (certificat expiré mais horodaté accepté, R-10) ni de
        révocation. Renvoie un objet IsTrusted, Status, Signer, RootSubject, RootThumbprint et Reason ;
        Reason explique le refus en français (racine inconnue : nom et empreinte de la racine rencontrée).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$TrustedRootThumbprint
    )

    $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    $result = [pscustomobject]@{
        Path           = $Path
        IsTrusted      = $false
        Status         = [string]$signature.Status
        Signer         = $null
        RootSubject    = $null
        RootThumbprint = $null
        Reason         = $null
    }
    if ($signature.SignerCertificate) { $result.Signer = $signature.SignerCertificate.Subject }

    if ($signature.Status -ne 'Valid') {
        $result.Reason = "Signature Authenticode non valide ($($result.Status))."
        return $result
    }
    if ($result.Signer -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
        $result.Reason = "Signataire hors de l'organisation Microsoft Corporation : $($result.Signer)."
        return $result
    }

    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreNotTimeValid
        [void]$chain.Build($signature.SignerCertificate)
        $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
        $result.RootSubject = $root.Subject
        $result.RootThumbprint = $root.Thumbprint.ToUpperInvariant()
        $selfSigned = ($root.Subject -eq $root.Issuer)
    } finally {
        $chain.Reset()
    }

    $trusted = @($TrustedRootThumbprint | ForEach-Object { $_.ToUpperInvariant() })
    if (-not $selfSigned) {
        $result.Reason = "Chaîne de certificats incomplète : elle s'arrête à $($result.RootSubject), qui n'est pas une racine."
    } elseif ($trusted -notcontains $result.RootThumbprint) {
        $result.Reason = "Racine inconnue : $($result.RootSubject) (empreinte $($result.RootThumbprint)) absente de integrity.trustedRootThumbprints. Téléchargement refusé."
    } else {
        $result.IsTrusted = $true
    }
    $result
}
