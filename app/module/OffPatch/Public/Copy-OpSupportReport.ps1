function Copy-OpSupportReport {
    <#
    .SYNOPSIS
        Rapatrie dans rapports\ du poste les rapports d'intervention déjà présents sur un support OffPatch.

    .DESCRIPTION
        Cahier des charges 7.4, étape 4, avant toute copie vers le support. Seulement si la destination contient déjà
        OffPatch (fichier offpatch.root) : chaque rapport (*.html) de son dossier rapports\ est copié dans rapports\
        du poste. Un rapport identique déjà présent (même taille, même SHA-256) est ignoré ; un nom déjà pris par un
        autre contenu reçoit le suffixe _2, _3…, comme à l'écriture d'un rapport : aucun rapport n'est écrasé.
        Copie atomique (fichier temporaire puis renommage). Rien n'est supprimé du support. Un rapport illisible est
        journalisé en avertissement sans arrêter les autres.
        Renvoie un objet par rapport : Source, Path (chemin sur le poste, vide si ignoré) et Status (Copied,
        AlreadyPresent ou Failed).

    .PARAMETER Destination
        Racine d'OffPatch sur le support, en général la racine du lecteur (E:\).

    .PARAMETER Root
        Racine de l'outil sur le poste ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Copy-OpSupportReport -Destination F:\ -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $source = Get-OpPath -Name Reports -Root $Destination
    if (-not (Test-Path -LiteralPath (Join-Path $Destination 'offpatch.root') -PathType Leaf) -or -not (Test-Path -LiteralPath $source -PathType Container)) { return }
    $reports = Get-OpPath -Name Reports -Root $Root

    foreach ($file in @(Get-ChildItem -LiteralPath $source -Filter '*.html' -File -ErrorAction Stop)) {
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $name = $file.Name
            $status = 'Copied'
            for ($n = 2; Test-Path -LiteralPath (Join-Path $reports $name); $n++) {
                $existing = Get-Item -LiteralPath (Join-Path $reports $name)
                if ($existing.Length -eq $file.Length -and (Get-FileHash -LiteralPath $existing.FullName -Algorithm SHA256 -ErrorAction Stop).Hash -eq $hash) {
                    $status = 'AlreadyPresent'
                    break
                }
                $name = "${base}_$n.html"
            }
            if ($status -eq 'AlreadyPresent') {
                [pscustomobject]@{ Source = $file.FullName; Path = ''; Status = $status }
                continue
            }
            $path = Join-Path $reports $name
            if (-not $PSCmdlet.ShouldProcess($path, "Rapatriement du rapport $($file.Name)")) { continue }
            New-Item -ItemType Directory -Force -Path $reports -ErrorAction Stop | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination "$path.tmp" -Force -ErrorAction Stop
            Move-Item -LiteralPath "$path.tmp" -Destination $path -Force -ErrorAction Stop
            Write-OpLog "Rapport rapatrié du support : $($file.Name) → $path."
            [pscustomobject]@{ Source = $file.FullName; Path = $path; Status = $status }
        } catch {
            Write-OpLog "Rapport du support non rapatrié ($($file.Name)) : $($_.Exception.Message)" -Level WARN
            [pscustomobject]@{ Source = $file.FullName; Path = ''; Status = 'Failed' }
        }
    }
}
