function Invoke-OpDepotUpdate {
    <#
    .SYNOPSIS
        Met à jour le dépôt ; avec -ListOnly, affiche seulement ce qui serait récupéré, sans rien télécharger.

    .DESCRIPTION
        Face Dépôt (cahier des charges 7.1). Charge la configuration et le manifeste, interroge le catalogue selon
        catalog-queries.json, ajoute les éléments épinglés, résout et contrôle chaque lien (requêtes HEAD, hôtes de
        allowedDomains), puis compare la taille des nouveautés à l'espace libre du volume du dépôt.
        -ListOnly s'arrête là : rien n'est téléchargé ni écrit, hormis le journal. Le téléchargement lui-même arrive
        avec les tâches suivantes de la phase 2 ; sans -ListOnly, la fonction le signale par une erreur.
        Renvoie un objet : Items (éléments de Get-OpDepotPlan), DownloadBytes (fichiers à télécharger, comptés une
        fois), UnknownSizeCount, FreeBytes (volume du dépôt, $null si illisible), EnoughSpace, ErrorCount.

    .PARAMETER ListOnly
        Interroge le catalogue et contrôle les liens sans rien télécharger.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Invoke-OpDepotUpdate -ListOnly

    .EXAMPLE
        (Invoke-OpDepotUpdate -ListOnly).Items | Select-Object Target, Category, Kb, ResultingUbr, Version
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$ListOnly,
        [string]$Root,
        [datetime]$Now = (Get-Date)
    )

    if (-not $ListOnly) {
        throw 'Téléchargement du dépôt pas encore disponible : utiliser -ListOnly.'
    }
    if (-not $Root) { $Root = Get-OpRoot }
    try {
        $configuration = Get-OpConfiguration -Root $Root
        $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)
        Write-OpLog "Mise à jour du dépôt (-ListOnly) : cibles $(@($configuration.Settings.targets) -join ', '), aucun téléchargement."
        $items = @(Get-OpDepotPlan -Configuration $configuration -Manifest $manifest -Now $Now)
    } catch {
        # Catalogue injoignable, page non reconnue, manifeste invalide : l'erreur est journalisée puis relancée.
        Write-OpLog -Level ERROR -Message "Mise à jour du dépôt (-ListOnly) interrompue : $($_.Exception.Message)"
        throw
    }

    # Fichiers à télécharger, comptés une fois (une checkpoint peut être jointe à plusieurs éléments).
    $seen = @{}
    $bytes = [long]0
    $unknown = 0
    $errorCount = 0
    foreach ($item in $items) {
        foreach ($f in $item.Files) {
            if ($f.Error) {
                $errorCount++
                Write-OpLog -Level ERROR -Message "Dépôt, $($item.Id) : $($f.FileName) refusé. $($f.Error)"
                continue
            }
            if ($f.InDepot) {
                Write-OpLog "Dépôt, $($item.Id) : $($f.FileName) déjà au dépôt."
                continue
            }
            Write-OpLog "Dépôt, $($item.Id) : $($f.FileName) à télécharger ($(@($f.Hosts) -join ' -> '))."
            if ($seen.ContainsKey($f.FileName.ToLowerInvariant())) { continue }
            $seen[$f.FileName.ToLowerInvariant()] = $true
            if ($null -eq $f.SizeBytes) { $unknown++ } else { $bytes += $f.SizeBytes }
        }
    }

    $free = Get-OpFreeSpace -Path (Get-OpPath -Name Depot -Root $Root)
    $enough = $null
    if ($null -ne $free) { $enough = ($bytes -le $free) }
    $summary = "Dépôt (-ListOnly) : {0} fichier(s) à télécharger, {1:N0} octets" -f $seen.Count, $bytes
    if ($unknown -gt 0) { $summary += " (taille inconnue pour $unknown fichier(s))" }
    if ($null -ne $free) { $summary += ", espace libre {0:N0} octets" -f $free }
    Write-OpLog $summary
    if ($enough -eq $false) { Write-OpLog -Level WARN -Message ("Dépôt : espace insuffisant, il manque {0:N0} octets : la mise à jour s'arrêterait avant tout téléchargement." -f ($bytes - $free)) }
    if ($null -eq $free) { Write-OpLog -Level WARN -Message 'Dépôt : espace libre du volume illisible (chemin réseau ?).' }

    [pscustomobject]@{
        Items            = $items
        DownloadBytes    = $bytes
        DownloadCount    = $seen.Count
        UnknownSizeCount = $unknown
        FreeBytes        = $free
        EnoughSpace      = $enough
        ErrorCount       = $errorCount
    }
}
