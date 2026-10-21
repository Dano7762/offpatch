function Write-OpProgress {
    <#
    .SYNOPSIS
        Affiche l'avancement d'un traitement long dans la console de la CLI, sans l'écrire au journal.

    .DESCRIPTION
        Console : seulement si le journal a été ouvert avec -Console (Start-OpLog, Initialize-OpSession). Interface :
        si le journal a une file de messages, le message y est déposé (Kind Progress, Message), pour la ligne
        d'avancement de l'onglet Dépôt. Avec Bytes (et TotalBytes s'il est connu), le message est complété de
        « reçu / total (pourcentage) ». Ligne de la console préfixée de l'heure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        $Bytes,
        $TotalBytes
    )

    $log = $null
    if (Get-Variable -Name OpLog -Scope Script -ErrorAction SilentlyContinue) { $log = $script:OpLog }
    if (-not $log) { return }
    $console = $log.PSObject.Properties['Console'] -and $log.Console
    $queue = $null
    if ($log.PSObject.Properties['Queue']) { $queue = $log.Queue }
    if (-not $console -and -not $queue) { return }
    if ($null -ne $Bytes) {
        if ($TotalBytes -gt 0) { $Message += ' {0} / {1} ({2:N0} %)' -f (Format-OpSize $Bytes), (Format-OpSize $TotalBytes), (100 * [double]$Bytes / $TotalBytes) }
        else { $Message += ' {0} reçus' -f (Format-OpSize $Bytes) }
    }
    if ($queue) { $queue.Enqueue([pscustomobject]@{ Kind = 'Progress'; Message = $Message.Trim() }) }
    if ($console) { Write-Host ('{0:HH:mm:ss} {1}' -f (Get-Date), $Message) }
}
