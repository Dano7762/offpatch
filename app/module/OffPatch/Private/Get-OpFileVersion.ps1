function Get-OpFileVersion {
    <#
    .SYNOPSIS
        Lit la version d'un exécutable (FileVersion) : mpam-fe.exe, plateforme Defender.

    .DESCRIPTION
        Lecture seule (cahier des charges 7.1, 8.3 ; R-06). Pour mpam-fe.exe, FileVersion est la version des
        définitions (AntivirusSignatureVersion après application) ; pour la plateforme, la version de la plateforme
        (AMProductVersion). Seuls les nombres du début de FileVersion sont lus (un suffixe de compilation est ignoré).
        Renvoie un [version], ou $null si le fichier ne porte aucune version lisible.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $text = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.FileVersion
    $match = [regex]::Match([string]$text, '^\s*(\d+(\.\d+){1,3})')
    if (-not $match.Success) { return $null }
    [version]$match.Groups[1].Value
}
