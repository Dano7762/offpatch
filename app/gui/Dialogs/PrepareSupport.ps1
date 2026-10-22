# Assistant « Préparer un support » (cahier des charges 7.4) : lecteur de destination, cibles et sources Office à
# embarquer, contrôle du système de fichiers et de l'espace libre. Affichage et câblage seulement : le contenu et les
# contrôles viennent de Get-OpSupportPlan (module, lecture seule). La copie arrive avec la tâche suivante de la phase 7.

function Get-OpSupportDriveList {
    <#
    .SYNOPSIS
        Lecteurs proposés comme support : prêts, amovibles ou fixes, ni celui du système ni celui de l'outil.

    .PARAMETER Root
        Racine de l'outil (son lecteur est écarté).

    .PARAMETER Drives
        Lecteurs à examiner (tests) ; par défaut, ceux du PC.

    .EXAMPLE
        Get-OpSupportDriveList -Root $root
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [object[]]$Drives = [System.IO.DriveInfo]::GetDrives()
    )

    $excluded = @([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Root)), "$($env:SystemDrive)\")
    foreach ($d in $Drives) {
        if (-not $d.IsReady -or @('Removable', 'Fixed') -notcontains [string]$d.DriveType -or $excluded -contains $d.Name) { continue }
        $name = $d.VolumeLabel
        if (-not $name) { $name = 'sans nom' }
        [pscustomobject]@{
            Root  = $d.Name
            Label = '{0} — {1} ({2}, {3:N1} Go libres sur {4:N1} Go)' -f $d.Name, $name, $d.DriveFormat, ($d.AvailableFreeSpace / 1GB), ($d.TotalSize / 1GB)
        }
    }
}

function Get-OpSupportPlanText {
    <#
    .SYNOPSIS
        Textes de l'assistant à partir du plan de support : résumé, refus, avertissements.

    .PARAMETER Plan
        Résultat de Get-OpSupportPlan.

    .EXAMPLE
        (Get-OpSupportPlanText -Plan $plan).Summary
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    $summary = 'Dépôt retenu : {0} élément(s), {1:N2} Go ; outil : {2:N1} Mo.' -f @($Plan.Items).Count, ($Plan.DepotBytes / 1GB), ($Plan.ToolBytes / 1MB)
    if ($Plan.Volume -and $Plan.Volume.IsReady) {
        $summary += ' Support {0} : {1}, {2:N1} Go libres ; à copier : {3:N2} Go.' -f $Plan.Volume.Root, $Plan.Volume.FileSystem, ($Plan.Volume.FreeBytes / 1GB), ($Plan.ToCopyBytes / 1GB)
    }
    [pscustomobject]@{ Summary = $summary; Blocking = (@($Plan.Blocking) -join [Environment]::NewLine); Warnings = (@($Plan.Warnings) -join [Environment]::NewLine) }
}

function Show-OpSupportView {
    <#
    .SYNOPSIS
        Recalcule le plan de support pour le lecteur et la sélection affichés, puis met l'assistant à jour.

    .PARAMETER Dialog
        Assistant renvoyé par Import-OpPrepareSupportWindow.

    .EXAMPLE
        Show-OpSupportView -Dialog $d
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Dialog
    )

    $c = $Dialog.Controls
    $drive = $c.SupportDrive.SelectedItem
    $c.BtnSupportPrepare.IsEnabled = $false
    $c.SupportBlocking.Visibility = 'Collapsed'
    $c.SupportWarnings.Visibility = 'Collapsed'
    if (-not $drive) {
        $c.SupportSummary.Text = 'Aucun lecteur disponible : brancher une clé USB ou un disque externe, puis « Actualiser ».'
        return
    }
    $targets = @($c.SupportTargets.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Content })
    $sources = @($c.SupportSources.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag.Id })
    try {
        $plan = Get-OpSupportPlan -Destination $drive.Root -Targets $targets -OfficeSources $sources -Root $Dialog.Root
    } catch {
        $c.SupportSummary.Text = "Contrôle du support impossible : $($_.Exception.Message)"
        return
    }
    $text = Get-OpSupportPlanText -Plan $plan
    $c.SupportSummary.Text = $text.Summary
    if ($text.Blocking) { $c.SupportBlockingText.Text = $text.Blocking; $c.SupportBlocking.Visibility = 'Visible' }
    if ($text.Warnings) { $c.SupportWarningsText.Text = $text.Warnings; $c.SupportWarnings.Visibility = 'Visible' }
    $Dialog | Add-Member -NotePropertyName Plan -NotePropertyValue $plan -Force
}

function Import-OpPrepareSupportWindow {
    <#
    .SYNOPSIS
        Charge et remplit l'assistant « Préparer un support », sans l'afficher.

    .DESCRIPTION
        PrepareSupport.xaml par Import-OpMainWindow -Path. Lecteurs proposés (Get-OpSupportDriveList), cibles et
        sources Office cochées comme dans la sélection du dépôt (Get-OpDepotSelection), contrôles recalculés à
        chaque changement. « Préparer le support » reste grisé jusqu'à la tâche de copie. Thread STA requis.

    .PARAMETER Root
        Racine de l'outil.

    .PARAMETER Drives
        Lecteurs à proposer (tests) ; par défaut, ceux du PC.

    .EXAMPLE
        $d = Import-OpPrepareSupportWindow -Root $root; [void]$d.Window.ShowDialog()
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [object[]]$Drives = [System.IO.DriveInfo]::GetDrives()
    )

    $d = Import-OpMainWindow -Path (Join-Path $PSScriptRoot 'PrepareSupport.xaml')
    $d | Add-Member -NotePropertyName Root -NotePropertyValue $Root
    $c = $d.Controls
    $selection = Get-OpDepotSelection -Root $Root
    foreach ($target in @($selection.AvailableTargets)) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = $target
        $box.IsChecked = @($selection.Targets) -contains $target
        $box.Margin = '0,2'
        $box.Tag = $d
        $box.Add_Click({ Show-OpSupportView -Dialog $this.Tag })
        [void]$c.SupportTargets.Children.Add($box)
    }
    foreach ($source in @($selection.OfficeSources)) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = '{0} ({1})' -f $source.Id, (@($source.Languages) -join ', ')
        $box.IsChecked = [bool]$source.Enabled
        $box.Margin = '0,2'
        $box.Tag = [pscustomobject]@{ Id = $source.Id; Dialog = $d }
        $box.Add_Click({ Show-OpSupportView -Dialog $this.Tag.Dialog })
        [void]$c.SupportSources.Children.Add($box)
    }
    $c.SupportDrive.ItemsSource = @(Get-OpSupportDriveList -Root $Root -Drives $Drives)
    if ($c.SupportDrive.Items.Count -gt 0) { $c.SupportDrive.SelectedIndex = 0 }
    $c.SupportDrive.Tag = $d
    $c.SupportDrive.Add_SelectionChanged({ Show-OpSupportView -Dialog $this.Tag })
    $c.BtnSupportRefresh.Tag = $d
    $c.BtnSupportRefresh.Add_Click({
            $dialog = $this.Tag
            $dialog.Controls.SupportDrive.ItemsSource = @(Get-OpSupportDriveList -Root $dialog.Root)
            if ($dialog.Controls.SupportDrive.Items.Count -gt 0) { $dialog.Controls.SupportDrive.SelectedIndex = 0 }
            Show-OpSupportView -Dialog $dialog
        })
    $c.BtnSupportPrepare.ToolTip = 'La copie sur le support arrive avec la prochaine version.'
    Show-OpSupportView -Dialog $d
    $d
}

function Show-OpPrepareSupport {
    <#
    .SYNOPSIS
        Ouvre l'assistant « Préparer un support » (onglet Dépôt).

    .PARAMETER Root
        Racine de l'outil.

    .PARAMETER Owner
        Fenêtre principale (centrage, modalité).

    .EXAMPLE
        Show-OpPrepareSupport -Root $ui.Root -Owner $ui.Window
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [System.Windows.Window]$Owner
    )

    $d = Import-OpPrepareSupportWindow -Root $Root
    if ($Owner) { $d.Window.Owner = $Owner }
    [void]$d.Window.ShowDialog()
}
