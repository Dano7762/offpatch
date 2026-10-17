function New-OpRestorePoint {
    <#
    .SYNOPSIS
        Crée le point de restauration de la session, juste avant la première étape, si la protection est déjà active.

    .DESCRIPTION
        Cahier des charges 8.2 (point de restauration). Jamais bloquant :
          - createRestorePointBeforeSession faux : aucun point, motif « option désactivée » ;
          - protection du système inactive, indicateurs en désaccord ou illisibles (Get-OpSystemProtection) : aucun
            appel à Checkpoint-Computer, qui activerait la protection de lui-même ;
          - protection active : Checkpoint-Computer, puis Get-ComputerRestorePoint : point postérieur à l'appel,
            Created ; sinon point de moins de 24 heures, Existing (Windows n'en crée qu'un par 24 heures) ; sinon
            aucun point constaté. L'appel n'étant fait que sur une protection déjà active, ProtectionEnabled reste faux.
        Renvoie Status (Created, Existing ou None), Description, CreationTime, Reason et ProtectionEnabled, la forme
        lue par le rapport (8.8).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [string]$Description = 'OffPatch : avant les mises à jour'
    )

    function ConvertTo-Result([string]$Status, [string]$Reason, $Point, [bool]$Enabled) {
        $when = $null
        $text = $null
        if ($Point) {
            $text = [string]$Point.Description
            $when = [Management.ManagementDateTimeConverter]::ToDateTime([string]$Point.CreationTime)
        }
        [pscustomobject]@{ Status = $Status; Description = $text; CreationTime = $when; Reason = $Reason; ProtectionEnabled = $Enabled }
    }
    function Get-RecentPoint([datetime]$Since) {
        @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationTime) -ge $Since } |
                Sort-Object -Property { [Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationTime) } -Descending) | Select-Object -First 1
    }

    if (-not $Configuration.Settings.client.createRestorePointBeforeSession) { return (ConvertTo-Result 'None' 'Option désactivée (createRestorePointBeforeSession).' $null $false) }
    try { $before = Get-OpSystemProtection }
    catch {
        Write-OpLog "Point de restauration : protection du système illisible, aucun point : $($_.Exception.Message)" -Level WARN
        return (ConvertTo-Result 'None' "Protection du système illisible : $($_.Exception.Message)" $null $false)
    }
    if (-not $before.Active) {
        $reason = 'Protection du système inactive.'
        if ($before.Spp -ne $before.Storage) { $reason = "Indicateurs de protection en désaccord (SPP\Clients : $($before.Spp), Win32_ShadowStorage : $($before.Storage))." }
        Write-OpLog "Point de restauration : $reason Aucun point créé." -Level WARN
        return (ConvertTo-Result 'None' $reason $null $false)
    }
    if (-not $PSCmdlet.ShouldProcess($env:SystemDrive, "Création du point de restauration « $Description »")) { return }

    $start = (Get-Date).AddSeconds(-5)
    try {
        Checkpoint-Computer -Description $Description -ErrorAction Stop -WarningAction SilentlyContinue
        $point = Get-RecentPoint $start
        $status = 'Created'
        if (-not $point) { $point = Get-RecentPoint ((Get-Date).AddHours(-24)); $status = 'Existing' }
    } catch {
        Write-OpLog "Point de restauration non créé : $($_.Exception.Message)" -Level WARN
        return (ConvertTo-Result 'None' "Échec de Checkpoint-Computer : $($_.Exception.Message)" $null $false)
    }
    if (-not $point) {
        Write-OpLog 'Point de restauration : aucun point constaté après Checkpoint-Computer.' -Level WARN
        return (ConvertTo-Result 'None' 'Aucun point constaté après Checkpoint-Computer.' $null $false)
    }
    Write-OpLog "Point de restauration ($status) : $($point.Description)."
    ConvertTo-Result $status $null $point $false
}
