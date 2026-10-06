function Unblock-OpToolFile {
    <#
    .SYNOPSIS
        Retire la marque « fichier téléchargé » (flux Zone.Identifier) des fichiers de l'outil.

    .DESCRIPTION
        Au premier lancement depuis un support, les fichiers de l'outil copiés depuis Internet portent la marque
        « fichier téléchargé », qui peut faire refuser les scripts (cahier des charges 8.1). Unblock-File est appliqué
        aux scripts, modules, données et interfaces de l'outil : Lancer-OffPatch.cmd, app\ et config\. Le dépôt
        (depot\) n'est pas concerné. Renvoie le nombre de fichiers débloqués.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $extensions = '.ps1', '.psm1', '.psd1', '.cmd', '.json', '.xaml', '.template'
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $launcher = Join-Path $Root 'Lancer-OffPatch.cmd'
    if (Test-Path -Path $launcher -PathType Leaf) { $files.Add((Get-Item -Path $launcher)) }
    foreach ($folder in 'app', 'config') {
        $path = Join-Path $Root $folder
        if (-not (Test-Path -Path $path -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -Path $path -Recurse -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })) { $files.Add($f) }
    }

    $count = 0
    foreach ($file in $files) {
        $zone = Get-Item -Path $file.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue
        if (-not $zone) { continue }
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Retrait de la marque « fichier téléchargé »')) {
            Unblock-File -Path $file.FullName -ErrorAction Stop
            $count++
        }
    }
    $count
}
