function Show-OpHeader {
    <#
    .SYNOPSIS
        Remplit l'en-tête de la fenêtre : version de l'outil, date du dépôt, alerte de fraîcheur.

    .DESCRIPTION
        Cahier des charges 9. Affichage seul, à partir de Get-OpDepotStatus : l'alerte apparaît pour un dépôt plus
        ancien que staleDepotWarningDays, vide ou illisible (motif en infobulle), et disparaît sinon. Appelé sur le
        thread de l'interface, au démarrage et après une mise à jour du dépôt.

    .PARAMETER Controls
        Éléments nommés de la fenêtre (Import-OpMainWindow).

    .PARAMETER Status
        État du dépôt (Get-OpDepotStatus).

    .EXAMPLE
        Show-OpHeader -Controls $ui.Controls -Status (Get-OpDepotStatus)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][pscustomobject]$Status
    )

    $Controls.HeaderVersion.Text = ''
    if ($Status.ToolVersion) { $Controls.HeaderVersion.Text = "version $($Status.ToolVersion)" }
    $alert = $null
    switch ($Status.State) {
        'Unreadable' { $date = 'Dépôt illisible'; $alert = 'Manifeste du dépôt illisible' }
        'Empty' { $date = 'Dépôt vide'; $alert = 'Aucune mise à jour dans le dépôt' }
        default {
            $age = "il y a $($Status.AgeDays) jours"
            if ($Status.AgeDays -le 0) { $age = 'aujourd''hui' } elseif ($Status.AgeDays -eq 1) { $age = 'il y a 1 jour' }
            $date = 'Dépôt du {0:dd/MM/yyyy} ({1})' -f $Status.GeneratedAt, $age
            if ($Status.State -eq 'Stale') { $alert = "Dépôt de plus de $($Status.StaleDays) jours : le mettre à jour" }
        }
    }
    $Controls.HeaderDepotDate.Text = $date
    $Controls.HeaderAlertText.Text = [string]$alert
    $Controls.HeaderAlert.ToolTip = $Status.Error
    $Controls.HeaderAlert.Visibility = 'Collapsed'
    if ($alert) { $Controls.HeaderAlert.Visibility = 'Visible' }
}
