function Test-OpSupport {
    <#
    .SYNOPSIS
        Vérifie, en lecture seule, un support préparé : tailles des fichiers, puis SHA-256 des fichiers du manifeste.

    .DESCRIPTION
        Cahier des charges 7.4, étape 7, après Copy-OpSupport. Ne modifie rien.
          1. Marqueur offpatch.root et manifeste filtré du support (depot\manifest.json) lisibles.
          2. Tailles : chaque fichier de l'outil du poste (Lancer-OffPatch.cmd, app, config, tools…) présent sur le
             support avec la même taille ; chaque fichier du manifeste du support présent avec la taille du manifeste.
          3. Empreintes : SHA-256 de chaque fichier du manifeste du support (Test-OpItemFileHash), élément par élément,
             seulement si les tailles sont conformes (une taille fausse suffit à condamner la copie). C'est l'étape
             longue (plusieurs minutes pour quelques gigaoctets sur une clé USB) : avancement par élément, annulation
             entre deux éléments.
        Renvoie Destination, ItemCount, FileCount, Bytes (taille des fichiers du manifeste), Problems (écarts, texte),
        Ok (aucun écart, vérification complète), Cancelled et Seconds.

    .PARAMETER Destination
        Racine d'OffPatch sur le support (E:\).

    .PARAMETER Root
        Racine de l'outil sur le poste (tailles de référence des fichiers de l'outil) ; par défaut, celle retrouvée
        par le fichier offpatch.root.

    .PARAMETER CancellationToken
        Jeton d'annulation (interface) : consulté avant chaque élément.

    .EXAMPLE
        Test-OpSupport -Destination F:\ | Select-Object Ok, FileCount, Problems
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [string]$Root,
        [System.Threading.CancellationToken]$CancellationToken
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $Destination = [System.IO.Path]::GetFullPath($Destination)
    $started = Get-Date
    $problems = New-Object System.Collections.Generic.List[string]
    $result = { param([bool]$Cancelled)
        [pscustomobject]@{
            Destination = $Destination; ItemCount = @($items).Count; FileCount = @($manifestFiles).Count; Bytes = $bytes
            Problems = $problems.ToArray(); Ok = (-not $Cancelled -and $problems.Count -eq 0); Cancelled = $Cancelled
            Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    $items = @()
    $manifestFiles = @()
    $bytes = [long]0

    if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($Destination, 'offpatch.root')) -PathType Leaf)) { $problems.Add('offpatch.root absent du support.') }
    $depot = [System.IO.Path]::Combine($Destination, 'depot')
    try {
        $items = @((Read-OpManifest -Path ([System.IO.Path]::Combine($depot, 'manifest.json'))).items | Where-Object { $_ })
    } catch {
        $problems.Add("Manifeste du support illisible : $($_.Exception.Message)")
    }
    if ($items.Count -eq 0 -and $problems.Count -eq 0) { $problems.Add('Manifeste du support vide : aucune mise à jour à installer.') }
    $manifestFiles = @($items | ForEach-Object { @($_.files | Where-Object { $_ }) } | Sort-Object -Property path -Unique)
    foreach ($f in $manifestFiles) { $bytes += [long]$f.size }

    # Tailles : outil (référence : le poste), puis dépôt (référence : le manifeste du support).
    Write-OpProgress 'Vérification du support : tailles des fichiers'
    $tool = Get-OpToolFileList -Root $Root
    foreach ($relative in $tool.Keys) {
        $copy = Get-Item -LiteralPath ([System.IO.Path]::Combine($Destination, $relative)) -ErrorAction SilentlyContinue
        if (-not $copy) { $problems.Add("$relative : absent du support.") }
        elseif ($copy.Length -ne [long]$tool[$relative]) { $problems.Add("$relative : $($copy.Length) octets au lieu de $($tool[$relative]).") }
    }
    foreach ($f in $manifestFiles) {
        $copy = Get-Item -LiteralPath ([System.IO.Path]::Combine($depot, ([string]$f.path -replace '/', '\'))) -ErrorAction SilentlyContinue
        if (-not $copy) { $problems.Add("depot/$($f.path) : absent du support.") }
        elseif ($copy.Length -ne [long]$f.size) { $problems.Add("depot/$($f.path) : $($copy.Length) octets au lieu de $($f.size).") }
    }
    if ($problems.Count -gt 0) {
        Write-OpLog "Vérification du support $Destination : $($problems.Count) écart(s), empreintes non vérifiées." -Level ERROR
        foreach ($p in $problems) { Write-OpLog $p -Level ERROR }
        return (& $result $false)
    }

    # Empreintes, élément par élément.
    $script:OpCancellation = $CancellationToken
    try {
        for ($i = 0; $i -lt $items.Count; $i++) {
            Assert-OpNotCancelled
            Write-OpProgress ('Vérification du support {0}/{1} : {2}' -f ($i + 1), $items.Count, $items[$i].id)
            foreach ($p in @(Test-OpItemFileHash -Depot $depot -File @($items[$i].files | Where-Object { $_ }))) { $problems.Add("depot/$p") }
        }
    } catch [System.OperationCanceledException] {
        Write-OpLog "Vérification du support $Destination annulée." -Level WARN
        return (& $result $true)
    } finally {
        $script:OpCancellation = $null
    }
    if ($problems.Count -gt 0) {
        Write-OpLog "Vérification du support $Destination : $($problems.Count) écart(s) d'empreinte." -Level ERROR
        foreach ($p in $problems) { Write-OpLog $p -Level ERROR }
    } else {
        Write-OpLog "Support $Destination vérifié : $($manifestFiles.Count) fichier(s) du dépôt conformes (tailles et SHA-256), outil complet."
    }
    & $result $false
}
