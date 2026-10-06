function Test-OpManifest {
    <#
    .SYNOPSIS
        Contrôle un manifeste du dépôt (cahier des charges 7.2) et renvoie la liste des anomalies, en français ;
        liste vide si tout est cohérent.

    .DESCRIPTION
        Règles : schemaVersion 1 ; identifiants uniques ; catégorie connue ; cible (os win10 ou win11, arch x64 ou
        arm64) ; ordre entier ; requiresReboot booléen ; dépendances (prerequisites, runsAfter) vers un identifiant
        du manifeste ou un code de catégorie ; fichiers : chemin relatif à depot/, sans « .. », sous files/<sha256>/
        (le nom du dossier est le SHA-256 du fichier, section 5) ou sous office/, SHA-256 de 64 caractères
        hexadécimaux, taille positive ; cumulatives Windows : baseBuilds et resultingUbr ; source Office : canal,
        version, langues et dossier.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Manifest
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $categories = 'windows-lcu', 'windows-checkpoint', 'windows-ekb', 'windows-ssu', 'dotnet', 'defender-platform', 'defender', 'office-source'

    if ([int]$Manifest.schemaVersion -ne 1) { $errors.Add("manifest.json : schemaVersion $($Manifest.schemaVersion) non pris en charge (attendu : 1).") }
    $items = @($Manifest.items | Where-Object { $null -ne $_ })
    $ids = @{}
    foreach ($item in $items) {
        if (-not $item.id) { $errors.Add('manifest.json : élément sans identifiant.') ; continue }
        if ($ids.ContainsKey($item.id)) { $errors.Add("manifest.json : identifiant en double « $($item.id) ».") } else { $ids[$item.id] = $true }
    }

    foreach ($item in $items) {
        $label = "manifest.json, $($item.id)"
        if ($categories -notcontains $item.category) { $errors.Add("$label : catégorie inconnue « $($item.category) ».") }
        if ($item.category -ne 'office-source') {
            if (@('win10', 'win11') -notcontains $item.target.os -or @('x64', 'arm64') -notcontains $item.target.arch) {
                $errors.Add("$label : cible invalide (os win10 ou win11, arch x64 ou arm64).")
            }
        }
        if ($null -eq $item.PSObject.Properties['order'] -or ($item.order -isnot [int] -and $item.order -isnot [long])) { $errors.Add("$label : order doit être un entier.") }
        if ($null -eq $item.PSObject.Properties['requiresReboot'] -or $item.requiresReboot -isnot [bool]) { $errors.Add("$label : requiresReboot doit valoir true ou false.") }
        foreach ($field in 'prerequisites', 'runsAfter') {
            if ($null -eq $item.PSObject.Properties[$field]) { continue }
            foreach ($dep in @($item.$field)) {
                if ($dep -and -not $ids.ContainsKey($dep) -and $categories -notcontains $dep) {
                    $errors.Add("$label : $field cite « $dep », ni identifiant du manifeste ni code de catégorie.")
                }
            }
        }
        if ($item.category -eq 'windows-lcu') {
            if (@($item.baseBuilds).Count -eq 0) { $errors.Add("$label : baseBuilds est vide.") }
            if ($null -eq $item.PSObject.Properties['resultingUbr'] -or [int]$item.resultingUbr -lt 0) { $errors.Add("$label : resultingUbr absent ou négatif.") }
        }
        if ($item.category -eq 'office-source') {
            foreach ($field in 'channel', 'version', 'folder') { if (-not $item.$field) { $errors.Add("$label : $field absent.") } }
            if (@($item.languages).Count -eq 0) { $errors.Add("$label : languages est vide.") }
        }
        $files = @($item.files | Where-Object { $null -ne $_ })
        if ($files.Count -eq 0) { $errors.Add("$label : aucun fichier.") }
        foreach ($file in $files) {
            $path = [string]$file.path
            $flabel = "$label, fichier « $path »"
            if (-not $path -or [System.IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)') {
                $errors.Add("$flabel : chemin absent, absolu ou hors du dépôt.")
                continue
            }
            if ($file.sha256 -notmatch '^[0-9a-f]{64}$') { $errors.Add("$flabel : sha256 invalide (64 caractères hexadécimaux en minuscules).") }
            if ($null -eq $file.PSObject.Properties['size'] -or [int64]$file.size -lt 0) { $errors.Add("$flabel : taille absente ou négative.") }
            $parts = $path -split '[\\/]'
            if ($parts[0] -eq 'files') {
                if ($parts.Count -ne 3 -or $parts[1] -ne $file.sha256) { $errors.Add("$flabel : attendu files/<sha256>/<nom d'origine>, dossier nommé par le SHA-256 du fichier.") }
            } elseif ($parts[0] -ne 'office') {
                $errors.Add("$flabel : le chemin doit commencer par files/ ou office/.")
            }
        }
    }

    $errors.ToArray()
}
