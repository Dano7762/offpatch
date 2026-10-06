function Initialize-OpSession {
    <#
    .SYNOPSIS
        Prépare une opération d'OffPatch : racine de l'outil, journal et configuration validée.

    .DESCRIPTION
        Point de départ commun de l'interface et de la CLI. Retrouve la racine de l'outil (fichier offpatch.root),
        ouvre le journal de l'opération (face Dépôt : logs\depot_… ; face Installation : ProgramData\OffPatch\logs\
        session_…, section 10), puis charge et valide la configuration (Get-OpConfiguration). Une configuration
        incohérente lève une erreur qui liste toutes les anomalies, après les avoir écrites dans le journal.
        Renvoie un objet Root, Log, Configuration.

    .PARAMETER Kind
        Depot pour la mise à jour du dépôt, Session pour une intervention sur un PC.

    .PARAMETER Queue
        File de messages de l'interface (facultative) : chaque ligne du journal y est aussi déposée.

    .EXAMPLE
        $context = Initialize-OpSession -Kind Depot

    .EXAMPLE
        $context = Initialize-OpSession -Kind Session -Queue $queue
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Depot', 'Session')][string]$Kind,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue,
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $level = 'INFO'
    try {
        $settings = Read-OpJsonFile -Path (Join-Path (Get-OpPath -Name Config -Root $Root) 'settings.json')
        if (@('DEBUG', 'INFO', 'WARN', 'ERROR') -contains $settings.logging.level) { $level = $settings.logging.level }
    } catch {
        $level = 'INFO'
    }
    $logDirectory = $null
    if ($Kind -eq 'Depot') { $logDirectory = Get-OpPath -Name Logs -Root $Root }
    $log = Start-OpLog -Kind $Kind -Level $level -Queue $Queue -Directory $logDirectory
    Write-OpLog "OffPatch, opération $Kind, racine $Root"

    try {
        $configuration = Get-OpConfiguration -Root $Root
    } catch {
        Write-OpLog $_.Exception.Message -Level ERROR
        throw
    }
    Write-OpLog "Configuration chargée : cibles $(@($configuration.Settings.targets) -join ', ')" -Level DEBUG
    [pscustomobject]@{ Root = $Root; Log = $log; Configuration = $configuration }
}
