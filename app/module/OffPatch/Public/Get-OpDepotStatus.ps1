function Get-OpDepotStatus {
    <#
    .SYNOPSIS
        Décrit, en lecture seule, l'état du dépôt : date de mise à jour, âge, fraîcheur, version de l'outil.

    .DESCRIPTION
        Cahier des charges 8.2 (contrôle « Âge du dépôt ») et 9 (en-tête et onglet Dépôt). Lit depot\manifest.json.
        State : Ok, Stale (plus ancien que client.staleDepotWarningDays), Empty (aucun élément ou date absente) ou
        Unreadable (manifeste absent ou illisible, motif dans Error). L'âge est compté en jours entiers, en UTC.
        Renvoie ToolVersion, State, GeneratedAt (heure locale), AgeDays, StaleDays, ItemCount et Error.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER StaleDays
        Seuil de fraîcheur en jours ; par défaut client.staleDepotWarningDays de settings.json.

    .PARAMETER Now
        Date de référence (tests).

    .EXAMPLE
        Get-OpDepotStatus | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [int]$StaleDays = -1,
        [datetime]$Now = (Get-Date)
    )

    if (-not $Root) { $Root = Get-OpRoot }
    if ($StaleDays -lt 0) { $StaleDays = [int](Get-OpConfiguration -Root $Root).Settings.client.staleDepotWarningDays }
    $status = [pscustomobject]@{
        ToolVersion = [string](Get-Module -Name OffPatch | Select-Object -First 1 -ExpandProperty Version)
        State = 'Unreadable'; GeneratedAt = $null; AgeDays = $null; StaleDays = $StaleDays; ItemCount = 0; Error = $null
    }
    try {
        $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)
    } catch {
        $status.Error = $_.Exception.Message
        return $status
    }
    $status.ItemCount = @($manifest.items | Where-Object { $_ }).Count
    if ($status.ItemCount -eq 0 -or -not $manifest.generatedAt) {
        $status.State = 'Empty'
        return $status
    }
    $generated = [datetime]::Parse([string]$manifest.generatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    $status.GeneratedAt = $generated.ToLocalTime()
    $status.AgeDays = [int][math]::Floor(($Now.ToUniversalTime() - $generated).TotalDays)
    $status.State = 'Ok'
    if ($status.AgeDays -gt $StaleDays) { $status.State = 'Stale' }
    $status
}
