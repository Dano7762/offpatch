function ConvertTo-OpMaskedText {
    <#
    .SYNOPSIS
        Masque dans un texte toute chaîne qui a la forme d'une clé de produit.

    .DESCRIPTION
        OffPatch ne manipule aucune clé de produit (recentrage sur les mises à jour). Par précaution, les journaux
        d'OffPatch (Write-OpLog) masquent quand même toute suite de cinq groupes de cinq lettres ou chiffres séparés
        par des tirets, sans tenir compte de la casse : elle devient XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    [regex]::Replace($Text, '\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b', 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
