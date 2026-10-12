function Invoke-OpDepotPurge {
    <#
    .SYNOPSIS
        Purge le dépôt selon la rétention et liste les fichiers orphelins.

    .DESCRIPTION
        Cahier des charges 7.3. Les éléments à retirer sont choisis par Get-OpDepotPurgePlan (cumulatives Windows et
        cumulatives .NET au-delà de retention.windowsMonths, anciennes versions Defender ; éléments épinglés jamais
        retirés). Le manifeste est réécrit d'abord, de façon atomique, puis les fichiers que plus aucun élément gardé ne référence
        sont supprimés : une interruption entre les deux ne laisse que des orphelins, jamais un manifeste qui cite un
        fichier absent.
        Sources Office : pour chaque élément office-source, les autres versions de la source (dossier
        Office\Data\<version>\ et v64_<version>.cab) sont supprimées, seulement si v64.cab désigne la version du
        manifeste (R-07) ; elles s'ajoutent à RemovedItems (office-<source>-<version>) et à RemovedFiles.
        Orphelins : fichiers de depot/files/ et de la racine de depot/ que le manifeste ne cite pas (manifest.json,
        le dossier temporaire .tmp/ et les sources Office de office/ sont exclus). Ils sont listés ; avec
        -RemoveOrphans, ils ne sont supprimés qu'après confirmation (ou avec -Force).
        Renvoie RemovedItems (identifiants), RemovedFiles (chemins relatifs à depot/), FreedBytes, Orphans (chemins
        relatifs et tailles) et RemovedOrphans.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER RemoveOrphans
        Supprime aussi les fichiers orphelins, après confirmation.

    .PARAMETER Force
        Avec -RemoveOrphans : supprime sans demander (l'interface a déjà demandé la confirmation).

    .EXAMPLE
        Invoke-OpDepotPurge

    .EXAMPLE
        Invoke-OpDepotPurge -WhatIf

    .EXAMPLE
        Invoke-OpDepotPurge -RemoveOrphans
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [switch]$RemoveOrphans,
        [switch]$Force
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $depot = Get-OpPath -Name Depot -Root $Root
    $manifestPath = Get-OpPath -Name Manifest -Root $Root
    $configuration = Get-OpConfiguration -Root $Root
    $manifest = Read-OpManifest -Path $manifestPath
    $plan = Get-OpDepotPurgePlan -Manifest $manifest -Configuration $configuration

    $result = [pscustomobject]@{
        RemovedItems   = @()
        RemovedFiles   = @()
        FreedBytes     = [long]0
        Orphans        = @()
        RemovedOrphans = @()
    }

    $ids = @($plan.Removed | ForEach-Object { $_.id })
    if ($ids.Count -gt 0 -and $PSCmdlet.ShouldProcess($manifestPath, "Retrait de $($ids.Count) élément(s) : $($ids -join ', ')")) {
        $manifest.items = @($plan.Kept)
        Save-OpManifest -Manifest $manifest -Path $manifestPath -Confirm:$false
        $result.RemovedItems = $ids
        Write-OpLog "Purge : $($ids.Count) élément(s) retiré(s) du manifeste ($($ids -join ', '))."
        $removedFiles = New-Object System.Collections.Generic.List[string]
        foreach ($f in $plan.RemovedFiles) {
            $full = Join-Path $depot $f.Path
            try {
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                    $result.FreedBytes += $f.Size
                }
                $folder = Split-Path -Parent $full
                if ((Test-Path -LiteralPath $folder) -and -not (Get-ChildItem -LiteralPath $folder -Force | Select-Object -First 1)) { Remove-Item -LiteralPath $folder -Force -ErrorAction Stop }
                $removedFiles.Add($f.Path)
            } catch {
                # Fichier verrouillé : il restera orphelin et sera proposé au prochain passage.
                Write-OpLog -Level WARN -Message "Purge : $($f.Path) non supprimé. $($_.Exception.Message)"
            }
        }
        $result.RemovedFiles = $removedFiles.ToArray()
        Write-OpLog ("Purge : {0} fichier(s) supprimé(s), {1:N0} octets libérés." -f $removedFiles.Count, $result.FreedBytes)
    }

    # Sources Office (7.3, R-07) : seule la version du manifeste est gardée, et seulement si v64.cab la désigne ;
    # sinon (téléchargement interrompu, index illisible) rien n'est retiré de cette source.
    foreach ($item in @($manifest.items | Where-Object { $_.category -eq 'office-source' })) {
        $source = Join-Path $depot ($item.folder -replace '/', '\')
        $data = Join-Path $source 'Office\Data'
        try {
            $index = Get-OpOfficeSourceVersion -Path $source -WorkFolder (Join-Path (Get-OpPath -Name DepotTemp -Root $Root) "purge-$($item.id)")
        } catch {
            Write-OpLog -Level WARN -Message "Purge : source Office $($item.folder) non purgée. $($_.Exception.Message)"
            continue
        }
        if (-not $index -or [string]$index.Version -ne [string]$item.version) {
            Write-OpLog -Level WARN -Message "Purge : source Office $($item.folder) non purgée, son index ne désigne pas la version $($item.version) du manifeste."
            continue
        }
        foreach ($old in @($index.Versions | Where-Object { [string]$_ -ne [string]$item.version })) {
            $paths = @((Join-Path $data "$old"), (Join-Path $data "v64_$old.cab") | Where-Object { Test-Path -LiteralPath $_ })
            if (-not $PSCmdlet.ShouldProcess($data, "Suppression de la version $old de la source Office")) { continue }
            $size = [long](@(Get-ChildItem -LiteralPath $paths -File -Recurse -Force | Measure-Object -Property Length -Sum)[0].Sum)
            try {
                Remove-Item -LiteralPath $paths -Recurse -Force -ErrorAction Stop
            } catch {
                Write-OpLog -Level WARN -Message "Purge : version $old de $($item.folder) non supprimée. $($_.Exception.Message)"
                continue
            }
            $result.FreedBytes += $size
            $result.RemovedItems = @($result.RemovedItems) + ($item.id -replace "$([regex]::Escape([string]$item.version))$", "$old")
            $result.RemovedFiles = @($result.RemovedFiles) + @($paths | ForEach-Object { $_.Substring($depot.TrimEnd('\').Length + 1) -replace '\\', '/' })
            Write-OpLog ("Purge : version {0} de la source Office {1} supprimée, {2:N0} octets libérés." -f $old, $item.folder, $size)
        }
    }

    # Orphelins, d'après le manifeste tel qu'il est maintenant sur le disque (inchangé si -WhatIf).
    $current = (Read-OpManifest -Path $manifestPath).items
    $known = @{}
    foreach ($item in @($current)) { foreach ($f in @($item.files)) { if ($f) { $known[([string]$f.path -replace '\\', '/').ToLowerInvariant()] = $true } } }
    $orphans = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $depot) {
        $candidates = @(Get-ChildItem -LiteralPath $depot -File -Force | Where-Object { $_.Name -notmatch '^manifest\.json(\.tmp)?$' })
        $filesFolder = Get-OpPath -Name DepotFiles -Root $Root
        if (Test-Path -LiteralPath $filesFolder) { $candidates += @(Get-ChildItem -LiteralPath $filesFolder -File -Recurse -Force) }
        foreach ($c in $candidates) {
            $relative = $c.FullName.Substring($depot.TrimEnd('\').Length + 1) -replace '\\', '/'
            if (-not $known.ContainsKey($relative.ToLowerInvariant())) { $orphans.Add([pscustomobject]@{ Path = $relative; Size = $c.Length }) }
        }
    }
    $result.Orphans = $orphans.ToArray()
    foreach ($o in $orphans) { Write-OpLog -Level WARN -Message ("Purge : fichier orphelin {0} ({1:N0} octets), absent du manifeste." -f $o.Path, $o.Size) }

    if ($RemoveOrphans -and $orphans.Count -gt 0) {
        $removedOrphans = New-Object System.Collections.Generic.List[string]
        foreach ($o in $orphans) {
            $full = Join-Path $depot $o.Path
            if (-not $PSCmdlet.ShouldProcess($full, 'Suppression du fichier orphelin')) { continue }
            if (-not ($Force -or $PSCmdlet.ShouldContinue("Supprimer le fichier orphelin $($o.Path) ?", 'Purge du dépôt'))) { continue }
            Remove-Item -LiteralPath $full -Force -ErrorAction Stop
            $folder = Split-Path -Parent $full
            if ($folder -ne $depot -and -not (Get-ChildItem -LiteralPath $folder -Force | Select-Object -First 1)) { Remove-Item -LiteralPath $folder -Force }
            $removedOrphans.Add($o.Path)
            Write-OpLog "Purge : fichier orphelin $($o.Path) supprimé."
        }
        $result.RemovedOrphans = $removedOrphans.ToArray()
    }
    $result
}
