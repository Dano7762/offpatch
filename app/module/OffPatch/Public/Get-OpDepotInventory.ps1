function Get-OpDepotInventory {
    <#
    .SYNOPSIS
        Décrit, en lecture seule, le contenu du dépôt : un élément du manifeste par ligne, taille, état des fichiers.

    .DESCRIPTION
        Cahier des charges 9 (onglet Dépôt). Pour chaque élément de depot\manifest.json : cible (os-arch, ou
        « Office <canal> »), catégorie et son libellé, KB ou version, date de publication, taille (somme de ses
        fichiers) et état de ses fichiers sur le disque : Complet, ou le nombre de fichiers absents ou de taille
        différente du manifeste. Contrôle rapide de présence et de taille : le SHA-256 complet est vérifié par
        l'installation (R-10). Taille totale : chaque fichier compté une fois (fichiers partagés, section 5).
        Renvoie Status (Get-OpDepotStatus), Items (Size : taille lisible), TotalBytes et TotalSize ; manifeste
        illisible : Items vide.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        (Get-OpDepotInventory).Items | Format-Table Target, CategoryLabel, Detail, ReleaseDate, SizeBytes, Integrity
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $status = Get-OpDepotStatus -Root $Root
    $items = New-Object System.Collections.Generic.List[object]
    $sizes = @{}
    if ($status.State -ne 'Unreadable') {
        $depot = Get-OpPath -Name Depot -Root $Root
        foreach ($m in @((Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)).items | Where-Object { $_ })) {
            $missing = 0
            $wrongSize = 0
            $size = [long]0
            $files = @()
            if ($m.PSObject.Properties['files']) { $files = @($m.files | Where-Object { $_ }) }
            foreach ($f in $files) {
                $size += [long]$f.size
                $sizes[[string]$f.path] = [long]$f.size
                $info = Get-Item -LiteralPath (Join-Path $depot ([string]$f.path -replace '/', '\')) -ErrorAction SilentlyContinue
                if (-not $info) { $missing++ } elseif ($info.Length -ne [long]$f.size) { $wrongSize++ }
            }
            $integrity = 'Complet'
            if ($missing -gt 0) { $integrity = "$missing fichier(s) absent(s)" }
            elseif ($wrongSize -gt 0) { $integrity = "$wrongSize fichier(s) de taille différente" }
            $target = ''
            if ($m.category -eq 'office-source') { $target = "Office $($m.channel)" }
            elseif ($m.PSObject.Properties['target']) { $target = '{0}-{1}' -f $m.target.os, $m.target.arch }
            $detail = ''
            if ($m.PSObject.Properties['kb'] -and $m.kb) { $detail = [string]$m.kb }
            elseif ($m.PSObject.Properties['version']) { $detail = [string]$m.version }
            $date = ''
            if ($m.PSObject.Properties['releaseDate']) { $date = [string]$m.releaseDate }
            $items.Add([pscustomobject]@{
                    Id = [string]$m.id; Target = $target; Category = [string]$m.category; CategoryLabel = ConvertTo-OpCategoryLabel ([string]$m.category)
                    Detail = $detail; ReleaseDate = $date; SizeBytes = $size; Size = Format-OpSize $size; Integrity = $integrity
                })
        }
    }
    $total = [long]0
    foreach ($s in $sizes.Values) { $total += $s }
    [pscustomobject]@{ Status = $status; Items = $items.ToArray(); TotalBytes = $total; TotalSize = Format-OpSize $total }
}
