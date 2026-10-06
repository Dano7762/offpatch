function ConvertTo-OpMaskedText {
    <#
    .SYNOPSIS
        Masque toute clé de produit dans un texte : la clé saisie sous toutes ses formes, et le motif générique.

    .DESCRIPTION
        Une clé de produit n'est jamais écrite dans un fichier persistant ni dans un journal (CLAUDE.md, cahier des
        charges 8.5 et 11). Remplacements, sans tenir compte de la casse :
          - la clé saisie (ProductKey), avec tirets puis sans tirets ;
          - toute suite de cinq groupes de cinq lettres ou chiffres séparés par des tirets (forme d'une clé).
        Chaque occurrence devient XXXXX-XXXXX-XXXXX-XXXXX-XXXXX (sans tirets : 25 X).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$ProductKey
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $masked = $Text
    if ($ProductKey) {
        $withDashes = $ProductKey.Trim()
        $withoutDashes = $withDashes -replace '-', ''
        $masked = [regex]::Replace($masked, [regex]::Escape($withDashes), 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', $options)
        if ($withoutDashes.Length -ge 25) {
            $masked = [regex]::Replace($masked, [regex]::Escape($withoutDashes), ('X' * $withoutDashes.Length), $options)
        }
    }
    [regex]::Replace($masked, '\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b', 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX', $options)
}
