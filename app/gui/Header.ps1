function Get-OpDepotStatusText {
    <#
    .SYNOPSIS
        Prépare les textes de l'état du dépôt : date et âge, alerte de fraîcheur (en-tête, onglet Dépôt).

    .DESCRIPTION
        Sans WPF. Alerte pour un dépôt plus ancien que staleDepotWarningDays, vide ou illisible ; $null sinon.
        Renvoie Date, Alert et Detail (motif d'un manifeste illisible).

    .PARAMETER Status
        État du dépôt (Get-OpDepotStatus).

    .EXAMPLE
        (Get-OpDepotStatusText -Status (Get-OpDepotStatus)).Date
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Status
    )

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
    [pscustomobject]@{ Date = $date; Alert = $alert; Detail = $Status.Error }
}

function Show-OpHeader {
    <#
    .SYNOPSIS
        Remplit l'en-tête de la fenêtre : version de l'outil, date du dépôt, alerte de fraîcheur.

    .DESCRIPTION
        Cahier des charges 9. Affichage seul, à partir de Get-OpDepotStatus (textes de Get-OpDepotStatusText) :
        l'alerte apparaît pour un dépôt ancien, vide ou illisible (motif en infobulle), et disparaît sinon. Appelé
        sur le thread de l'interface, au démarrage et après une mise à jour du dépôt.

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

    $text = Get-OpDepotStatusText -Status $Status
    $Controls.HeaderVersion.Text = ''
    if ($Status.ToolVersion) { $Controls.HeaderVersion.Text = "version $($Status.ToolVersion)" }
    $Controls.HeaderDepotDate.Text = $text.Date
    $Controls.HeaderAlertText.Text = [string]$text.Alert
    $Controls.HeaderAlert.ToolTip = $text.Detail
    $Controls.HeaderAlert.Visibility = 'Collapsed'
    if ($text.Alert) { $Controls.HeaderAlert.Visibility = 'Visible' }
}

function Register-OpHeader {
    <#
    .SYNOPSIS
        Affiche le logo dans l'en-tête et comme icône de la fenêtre, et câble le lien du pied vers le dépôt du projet.

    .DESCRIPTION
        Logo lu dans OffPatch.jpg à côté de ce script, une seule fois (image figée, fichier libéré). Logo absent ou
        illisible : en-tête et icône par défaut, sans erreur. Le lien du pied s'ouvre dans le navigateur par défaut ;
        sans connexion, le navigateur affiche simplement une erreur.

    .PARAMETER Ui
        Fenêtre renvoyée par Import-OpMainWindow.

    .PARAMETER LogoPath
        Image du logo ; par défaut OffPatch.jpg à côté de ce script.

    .EXAMPLE
        Register-OpHeader -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [string]$LogoPath = (Join-Path $PSScriptRoot 'OffPatch.jpg')
    )

    if (Test-Path -LiteralPath $LogoPath -PathType Leaf) {
        try {
            $image = New-Object System.Windows.Media.Imaging.BitmapImage
            $image.BeginInit()
            $image.UriSource = New-Object System.Uri $LogoPath
            $image.CacheOption = 'OnLoad'
            $image.DecodePixelHeight = 256
            $image.EndInit()
            $image.Freeze()
            $Ui.Controls.HeaderLogo.Source = $image
            $Ui.Controls.HeaderLogo.Visibility = 'Visible'
            $Ui.Window.Icon = $image
        } catch {
            $Ui.Controls.HeaderLogo.Visibility = 'Collapsed'
        }
    }
    $Ui.Controls.FooterLink.Add_RequestNavigate({
            Start-Process -FilePath $_.Uri.AbsoluteUri
            $_.Handled = $true
        })
}
