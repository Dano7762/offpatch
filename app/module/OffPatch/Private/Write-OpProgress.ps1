function Write-OpProgress {
    <#
    .SYNOPSIS
        Affiche l'avancement d'un traitement long dans la console de la CLI, sans l'écrire au journal.

    .DESCRIPTION
        N'affiche rien si le journal n'a pas été ouvert avec -Console (Start-OpLog, Initialize-OpSession) : l'interface
        WPF et les tests ne reçoivent rien. Avec Bytes (et TotalBytes s'il est connu), le message est complété de
        « reçu / total (pourcentage) ». Ligne préfixée de l'heure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        $Bytes,
        $TotalBytes
    )

    $log = $null
    if (Get-Variable -Name OpLog -Scope Script -ErrorAction SilentlyContinue) { $log = $script:OpLog }
    if (-not $log -or -not $log.PSObject.Properties['Console'] -or -not $log.Console) { return }
    if ($null -ne $Bytes) {
        if ($TotalBytes -gt 0) { $Message += ' {0} / {1} ({2:N0} %)' -f (Format-OpSize $Bytes), (Format-OpSize $TotalBytes), (100 * [double]$Bytes / $TotalBytes) }
        else { $Message += ' {0} reçus' -f (Format-OpSize $Bytes) }
    }
    Write-Host ('{0:HH:mm:ss} {1}' -f (Get-Date), $Message)
}
