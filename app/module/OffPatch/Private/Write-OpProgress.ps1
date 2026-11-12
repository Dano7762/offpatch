function Write-OpProgress {
    <#
    .SYNOPSIS
        Affiche l'avancement d'un traitement long dans la console de la CLI, sans l'écrire au journal.

    .DESCRIPTION
        Console : seulement si le journal a été ouvert avec -Console (Start-OpLog, Initialize-OpSession). Interface :
        si le journal a une file de messages, le message y est déposé (Kind Progress, Message, Value, Indeterminate),
        pour la barre et la ligne d'avancement de l'onglet Dépôt. Avec Bytes (et TotalBytes s'il est connu), le message
        est complété de « reçu / total (pourcentage) ». Ligne de la console préfixée de l'heure.

        Fichier en cours (script:OpProgressFile, posé par Invoke-OpDepotUpdate : Index, Count, Name, Size, Done,
        Total) : le message de la file reprend le fichier i/n et son nom, et Value donne l'avancement global en octets
        (0 à 1) sur l'ensemble des fichiers à télécharger. Indeterminate : traitement sans progression connue (ODT,
        setup.exe /download), barre indéterminée.

        Throttle (boucles de téléchargement, appel à chaque relève) : file de messages au plus toutes les 2 s, console
        au plus toutes les 30 s. Un appel sans Throttle remet les deux délais à zéro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        $Bytes,
        $TotalBytes,
        [switch]$Indeterminate,
        [switch]$Throttle
    )

    $log = $null
    if (Get-Variable -Name OpLog -Scope Script -ErrorAction SilentlyContinue) { $log = $script:OpLog }
    if (-not $log) { return }
    $console = $log.PSObject.Properties['Console'] -and $log.Console
    $queue = $null
    if ($log.PSObject.Properties['Queue']) { $queue = $log.Queue }
    if (-not $console -and -not $queue) { return }

    $now = Get-Date
    $last = $null
    if (Get-Variable -Name OpProgressLast -Scope Script -ErrorAction SilentlyContinue) { $last = $script:OpProgressLast }
    if (-not $Throttle -or -not $last) {
        $script:OpProgressLast = @{ Queue = $now; Console = $now }
        $last = $script:OpProgressLast
        if ($Throttle) { return }
    } else {
        if ($queue -and ($now - $last.Queue).TotalSeconds -lt 2) { $queue = $null }
        if ($console -and ($now - $last.Console).TotalSeconds -lt 30) { $console = $false }
        if (-not $console -and -not $queue) { return }
        if ($queue) { $last.Queue = $now }
        if ($console) { $last.Console = $now }
    }

    $file = $null
    if (Get-Variable -Name OpProgressFile -Scope Script -ErrorAction SilentlyContinue) { $file = $script:OpProgressFile }
    $text = $Message
    if ($null -ne $Bytes) {
        if ($TotalBytes -gt 0) { $text += ' {0} / {1} ({2:N0} %)' -f (Format-OpSize $Bytes), (Format-OpSize $TotalBytes), (100 * [double]$Bytes / $TotalBytes) }
        else { $text += ' {0} reçus' -f (Format-OpSize $Bytes) }
    }
    if ($queue) {
        $value = $null
        $queueText = $text.Trim()
        if ($file) {
            $done = [double]$file.Done
            if ($null -ne $Bytes) {
                $done += [double]$Bytes
                $size = $TotalBytes
                if (-not ($size -gt 0)) { $size = $file.Size }
                $queueText = 'Fichier {0}/{1} : {2}, {3}' -f $file.Index, $file.Count, $file.Name, (Format-OpSize $Bytes)
                if ($size -gt 0) { $queueText += ' / {0} ({1:N0} %)' -f (Format-OpSize $size), (100 * [double]$Bytes / $size) }
            }
            if ($file.Total -gt 0) {
                $value = [Math]::Min([double]1, $done / $file.Total)
                if ($null -ne $Bytes) { $queueText += ' ; total {0:N0} %' -f (100 * $value) }
            }
        }
        $queue.Enqueue([pscustomobject]@{ Kind = 'Progress'; Message = $queueText; Value = $value; Indeterminate = [bool]$Indeterminate })
    }
    if ($console) { Write-Host ('{0:HH:mm:ss} {1}' -f $now, $text) }
}
