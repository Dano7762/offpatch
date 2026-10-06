function Read-OpJsonFile {
    <#
    .SYNOPSIS
        Lit un fichier JSON en UTF-8 et renvoie l'objet, ou lève une erreur qui nomme le fichier.

    .DESCRIPTION
        Les fichiers .json de l'outil sont toujours lus avec -Encoding UTF8 (CLAUDE.md). Fichier absent ou JSON
        invalide : erreur explicite avec le chemin, pour que le message du journal suffise à corriger.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Fichier de configuration absent : $Path"
    }
    try {
        Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Fichier de configuration illisible ($Path) : $($_.Exception.Message)"
    }
}
