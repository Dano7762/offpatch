function Get-OpRoot {
    <#
    .SYNOPSIS
        Retrouve la racine de l'outil, le dossier qui contient le fichier marqueur offpatch.root.

    .DESCRIPTION
        Remonte l'arborescence depuis StartPath (par défaut, le dossier du module) jusqu'au premier dossier qui
        contient offpatch.root. Aucune lettre de lecteur n'est mémorisée : le support peut changer de lettre d'un
        PC à l'autre, et même entre deux redémarrages (cahier des charges, section 5). Lève une erreur explicite si
        aucun marqueur n'est trouvé.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    $current = (Resolve-Path -Path $StartPath -ErrorAction Stop).ProviderPath
    while ($current) {
        if (Test-Path -Path (Join-Path $current 'offpatch.root') -PathType Leaf) {
            return $current
        }
        $parent = Split-Path -Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    throw "Racine d'OffPatch introuvable : aucun fichier offpatch.root au-dessus de $StartPath."
}
