function Write-OpInstallReport {
    <#
    .SYNOPSIS
        Écrit le rapport d'intervention de la session en cours et clôt la session de la CLI.

    .DESCRIPTION
        Cahier des charges 8.8. Rassemble ProgramData\OffPatch\temp\cli-session.json (début, relevé du PC avant,
        point de restauration, résultat des étapes exécutées par Invoke-OpInstallStep), le plan recalculé (étapes
        non exécutées, avec leur état), le relevé du PC après, l'état du réseau (hors ligne : rappel du mode Avion),
        la version de l'outil, la date du dépôt et le journal de session. Sans session en cours, le rapport décrit
        l'état du PC sans étape exécutée. Écrit le rapport par Save-OpReport, puis supprime cli-session.json.
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
    $sessionPath = Join-Path (Get-OpPath -Name ClientTemp) 'cli-session.json'
    $session = $null
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { $session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json }

    $done = @()
    $start = Get-Date
    $before = $after
    $restore = $null
    if ($session) {
        $done = @($session.Steps | Where-Object { $_ })
        $start = [datetime]$session.StartTime
        $before = $session.Before
        $restore = $session.RestorePoint
        if ($restore -and $restore.PSObject.Properties['CreationTime'] -and $restore.CreationTime) { $restore.CreationTime = [datetime]$restore.CreationTime }
    }
    $doneIds = @($done | ForEach-Object { $_.Id })
    $steps = @($done) + @($plan | Where-Object { -not $_.Id -or $doneIds -notcontains $_.Id })

    $offline = $false
    try { $offline = @(Get-OpNetworkConnection).Count -eq 0 } catch { Write-OpLog "État du réseau illisible : $($_.Exception.Message)" -Level WARN }
    $log = Get-Variable -Name OpLog -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $logPath = $null
    if ($log) { $logPath = $log.Path }
    $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)

    $report = [pscustomobject]@{
        StartTime    = $start
        EndTime      = Get-Date
        Before       = $before
        After        = $after
        Steps        = $steps
        LogPath      = $logPath
        Offline      = $offline
        RestorePoint = $restore
        ToolVersion  = [string](Get-Module -Name OffPatch | Select-Object -First 1 -ExpandProperty Version)
        DepotDate    = $manifest.generatedAt
    }
    $path = Save-OpReport -Session $report -Configuration $configuration -Root $Root -WhatIf:$WhatIfPreference -Confirm:$false
    if ($path -and $session -and $PSCmdlet.ShouldProcess($sessionPath, 'Clôture de la session de la CLI')) { Remove-Item -LiteralPath $sessionPath -Force -ErrorAction Stop }
    $path
}
