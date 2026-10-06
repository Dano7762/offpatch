function Test-OpProductKeyFormat {
    <#
    .SYNOPSIS
        Vérifie la forme d'une clé de produit avant de la passer à l'ODT.

    .DESCRIPTION
        L'ODT accepte une clé invalide sans erreur (code 0, R-08) : la forme est donc contrôlée avant, dans
        l'interface et dans la CLI. Forme attendue : cinq groupes de cinq caractères séparés par des tirets, dans
        l'alphabet BCDFGHJKMPQRTVWXY2346789, sans tenir compte de la casse. Une clé de forme valide n'est pas pour
        autant vérifiée : l'activation se fait en ligne (rapport : « clé enregistrée, activation non vérifiée, à
        réaliser en ligne »). La fonction ne journalise jamais la clé.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ProductKey
    )

    $ProductKey.Trim() -match '^(?i)[BCDFGHJKMPQRTVWXY2346789]{5}(-[BCDFGHJKMPQRTVWXY2346789]{5}){4}$'
}
