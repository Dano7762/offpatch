function Protect-OpLogFile {
    <#
    .SYNOPSIS
        Masque toute clé de produit dans un fichier journal, en le réécrivant dans son encodage d'origine.

    .DESCRIPTION
        L'ODT écrit la clé passée dans PIDKEY en clair dans son journal principal, en UTF-16 (R-08). Avant toute
        copie dans le dossier de session ou sur le support, et pour les journaux laissés dans TEMP, chaque fichier
        est relu dans son encodage d'origine, masqué par ConvertTo-OpMaskedText, puis réécrit dans le même encodage :
          - marque d'ordre des octets UTF-16 LE, UTF-16 BE ou UTF-8 : encodage correspondant, marque conservée ;
          - sans marque : UTF-16 LE si un octet sur deux est nul dans le début du fichier, UTF-8 sinon (sans marque).
        Le fichier n'est réécrit que s'il contenait une clé. Renvoie le nombre de remplacements effectués.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ProductKey
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    $writeBom = $false
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = New-Object System.Text.UnicodeEncoding($false, $true); $offset = 2; $writeBom = $true
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = New-Object System.Text.UnicodeEncoding($true, $true); $offset = 2; $writeBom = $true
    } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = New-Object System.Text.UTF8Encoding($true); $offset = 3; $writeBom = $true
    } else {
        # Sans marque : UTF-16 LE si les octets impairs du début sont presque tous nuls.
        $sample = [math]::Min($bytes.Length, 4096)
        $zeros = 0
        for ($i = 1; $i -lt $sample; $i += 2) { if ($bytes[$i] -eq 0) { $zeros++ } }
        if ($sample -ge 4 -and $zeros -ge ($sample / 2) * 0.8) {
            $encoding = New-Object System.Text.UnicodeEncoding($false, $false)
        } else {
            $encoding = New-Object System.Text.UTF8Encoding($false)
        }
    }

    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $masked = ConvertTo-OpMaskedText -Text $text -ProductKey $ProductKey
    if ($masked -ceq $text) { return 0 }

    $maskPattern = 'X{5}-X{5}-X{5}-X{5}-X{5}|X{25}'
    $count = [regex]::Matches($masked, $maskPattern).Count - [regex]::Matches($text, $maskPattern).Count
    if ($PSCmdlet.ShouldProcess($Path, 'Masquage de la clé de produit')) {
        $body = $encoding.GetBytes($masked)
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            if ($writeBom) { $preamble = $encoding.GetPreamble(); $stream.Write($preamble, 0, $preamble.Length) }
            $stream.Write($body, 0, $body.Length)
        } finally {
            $stream.Dispose()
        }
    }
    $count
}
