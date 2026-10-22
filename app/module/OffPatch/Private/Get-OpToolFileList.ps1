function Get-OpToolFileList {
    <#
    .SYNOPSIS
        Fichiers de l'outil copiés sur un support : chemin relatif à la racine et taille.

    .DESCRIPTION
        Cahier des charges 7.4 : fichiers de la racine (Lancer-OffPatch.cmd, offpatch.root, README.md, LICENSE) et
        dossiers app, config, tools ; journaux, rapports et dépôt n'en font pas partie. Renvoie une table ordonnée
        chemin relatif -> taille, partagée par le plan de copie et la vérification après copie.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $files = [ordered]@{}
    foreach ($name in 'Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE') {
        $path = Join-Path $Root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $files[$name] = (Get-Item -LiteralPath $path).Length }
    }
    foreach ($folder in 'app', 'config', 'tools') {
        $path = Join-Path $Root $folder
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $path -Recurse -File)) { $files[$f.FullName.Substring($Root.TrimEnd('\').Length + 1)] = $f.Length }
    }
    , $files
}
