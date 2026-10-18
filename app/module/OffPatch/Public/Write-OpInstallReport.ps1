function Write-OpInstallReport {
    <#
    .SYNOPSIS
        Écrit le rapport d'intervention de la session en cours et clôt la session de la CLI.

    .DESCRIPTION
        Cahier des charges 8.6, 8.8. Rassemble l'état de session state.json (début, relevé du PC avant, point de
        restauration, résultat des étapes exécutées par Invoke-OpInstallStep), le plan recalculé (étapes non
        exécutées, avec leur état), le relevé du PC après, l'état du réseau (hors ligne : rappel du mode Avion), la
        version de l'outil, la date du dépôt et les journaux de la session. Sans session en cours, le rapport décrit
        l'état du PC sans étape exécutée. Écrit le rapport par Save-OpReport, puis clôt la session : state.json est
        archivé dans les journaux (Complete-OpSessionState).
        Renvoie le chemin du rapport sur le support.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Write-OpInstallReport
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    $after = Get-OpSystemInfo -Root $Root
    $plan = @(Get-OpInstallPlan -Root $Root -SystemInfo $after)
    $session = Read-OpSessionState

    $done = @()
    $start = Get-Date
    $before = $after
    $restore = [pscustomobject]@{ Status = 'None'; Reason = 'Aucune étape exécutée : aucun point demandé.' }
    $logPaths = @()
    if ($session) {
        $done = @($session.steps | Where-Object { $_ })
        $start = [datetime]$session.startTime
        $before = $session.before
        $restore = $session.restorePoint
        if ($restore -and $restore.PSObject.Properties['CreationTime'] -and $restore.CreationTime) { $restore.CreationTime = [datetime]$restore.CreationTime }
        $logPaths = @($session.logPaths | Where-Object { $_ })
    }
    $doneIds = @($done | ForEach-Object { $_.Id })
    $steps = @($done) + @($plan | Where-Object { -not $_.Id -or $doneIds -notcontains $_.Id })

    $offline = $false
    try { $offline = @(Get-OpNetworkConnection).Count -eq 0 } catch { Write-OpLog "État du réseau illisible : $($_.Exception.Message)" -Level WARN }
    $log = Get-Variable -Name OpLog -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    # Un journal par appel de la CLI : ceux des étapes, puis celui du rapport.
    if ($log -and $log.Path -and $logPaths -notcontains $log.Path) { $logPaths += $log.Path }
    $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)

    $report = [pscustomobject]@{
        StartTime    = $start
        EndTime      = Get-Date
        Before       = $before
        After        = $after
        Steps        = $steps
        LogPath      = $logPaths
        Offline      = $offline
        RestorePoint = $restore
        ToolVersion  = [string](Get-Module -Name OffPatch | Select-Object -First 1 -ExpandProperty Version)
        DepotDate    = $manifest.generatedAt
    }
    $path = Save-OpReport -Session $report -Configuration $configuration -Root $Root -WhatIf:$WhatIfPreference -Confirm:$false
    if ($path -and $session) { [void](Complete-OpSessionState -WhatIf:$WhatIfPreference -Confirm:$false) }
    $path
}
