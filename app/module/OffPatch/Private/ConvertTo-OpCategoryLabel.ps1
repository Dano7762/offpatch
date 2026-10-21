function ConvertTo-OpCategoryLabel {
    <#
    .SYNOPSIS
        Libellé français d'une catégorie d'élément (interface, plan, inventaire du dépôt).

    .DESCRIPTION
        Catégories du manifeste (cahier des charges 7.2). Une catégorie inconnue est renvoyée telle quelle.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Category
    )

    $labels = @{
        'defender-platform' = 'Plateforme Defender'; 'defender' = 'Définitions Defender'; 'windows-ssu' = 'Pile de maintenance'
        'windows-checkpoint' = 'Cumulative de base (checkpoint)'; 'windows-lcu' = 'Cumulative Windows'
        'windows-ekb' = 'Passage de version (enablement package)'; 'dotnet' = '.NET Framework'; 'office-source' = 'Office'
    }
    if ($Category -and $labels.ContainsKey($Category)) { return $labels[$Category] }
    $Category
}
