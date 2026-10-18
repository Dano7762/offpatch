function Unregister-OpResumeTask {
    <#
    .SYNOPSIS
        Supprime la tâche planifiée OffPatch-Reprise si elle existe.

    .DESCRIPTION
        Cahier des charges 8.6 et 11 (aucune élévation persistante) : appelé en fin de session, et après la reprise
        pour ne pas relancer l'outil à chaque ouverture de session. Sans tâche, rien n'est fait. Renvoie vrai si une
        tâche a été supprimée.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string]$TaskName = 'OffPatch-Reprise'
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $false }
    if (-not $PSCmdlet.ShouldProcess($TaskName, 'Suppression de la tâche de reprise')) { return $false }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-OpLog "Tâche $TaskName supprimée."
    $true
}
