# Assistant « Préparer un support » (cahier des charges 7.4) : lecteur de destination, cibles et sources Office à
# embarquer, contrôle du système de fichiers et de l'espace libre, copie. Affichage et câblage seulement : le contenu et
# les contrôles viennent de Get-OpSupportPlan (module, lecture seule), la copie de Copy-OpSupport, dans un runspace.

# Copie sur le support (runspace) : journal de la face Dépôt, annulation entre deux dossiers par $OpCancel.
$script:OpSupportCopyScript = {
    param([string]$Root, [string]$Destination, [string[]]$Targets, [string[]]$OfficeSources)
    [void](Initialize-OpSession -Kind Depot -Queue $OpQueue -Root $Root)
    Copy-OpSupport -Destination $Destination -Targets $Targets -OfficeSources $OfficeSources -Root $Root -CancellationToken $OpCancel -Confirm:$false
}

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
    $c.BtnSupportPrepare.IsEnabled = $plan.CanPrepare
    $Dialog | Add-Member -NotePropertyName Plan -NotePropertyValue $plan -Force
}

function Import-OpPrepareSupportWindow {
    <#
    .SYNOPSIS
        Charge et remplit l'assistant « Préparer un support », sans l'afficher.

    .DESCRIPTION
        PrepareSupport.xaml par Import-OpMainWindow -Path. Lecteurs proposés (Get-OpSupportDriveList), cibles et
        sources Office cochées comme dans la sélection du dépôt (Get-OpDepotSelection), contrôles recalculés à
        chaque changement. « Préparer le support » (actif si le plan l'accepte) demande confirmation puis copie en
        arrière-plan (Start-OpSupportCopy) ; fermer la fenêtre pendant la copie demande son annulation, qui prend
        effet entre deux dossiers. Thread STA requis.

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
    $c.BtnSupportPrepare.Tag = $d
    $c.BtnSupportPrepare.Add_Click({
            $dialog = $this.Tag
            $question = "Préparer le support $($dialog.Plan.Destination) ? Les dossiers app, config, tools et ceux du dépôt y seront remplacés ; les rapports du support sont d'abord rapatriés sur ce poste."
            if ([System.Windows.MessageBox]::Show($question, 'OffPatch', 'YesNo', 'Question') -eq 'Yes') { Start-OpSupportCopy -Dialog $dialog }
        })
    $d.Window.Tag = $d
    $d.Window.Add_Closing({
            $dialog = $this.Tag
            if (-not $dialog.PSObject.Properties['CopyTask'] -or -not $dialog.CopyTask -or $dialog.CopyTask.Done) { return }
            $_.Cancel = $true
            Stop-OpBackgroundTask -Task $dialog.CopyTask -Confirm:$false
            $dialog.Controls.SupportProgress.Text = 'Annulation demandée : arrêt après le dossier en cours.'
        })
    Show-OpSupportView -Dialog $d
    $d
}

function Get-OpSupportCopyText {
    <#
    .SYNOPSIS
        Bilan affiché à la fin de la copie sur le support.

    .PARAMETER Result
        Résultat de Copy-OpSupport : Destination, Reports, Folders, Removed, Cancelled.

    .EXAMPLE
        Get-OpSupportCopyText -Result $result
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Result
    )

    if ($Result.Cancelled) { return "Préparation du support $($Result.Destination) annulée : le support n'est pas utilisable tant qu'elle n'a pas été refaite jusqu'au bout." }
    $seconds = [double]0
    foreach ($f in @($Result.Folders)) { $seconds += [double]$f.Seconds }
    $copied = @($Result.Reports | Where-Object { $_.Status -eq 'Copied' }).Count
    'Support {0} préparé en {1:N0} min : {2} copie(s), {3} rapport(s) rapatrié(s) sur ce poste, {4} dossier(s) obsolète(s) supprimé(s).' -f $Result.Destination, ($seconds / 60), @($Result.Folders).Count, $copied, @($Result.Removed).Count
}

function Start-OpSupportCopy {
    <#
    .SYNOPSIS
        Lance la copie sur le support en arrière-plan et affiche son avancement dans l'assistant.

    .DESCRIPTION
        Commandes grisées pendant la copie, « Fermer » devient « Annuler » (annulation entre deux dossiers). À la fin :
        bilan (Get-OpSupportCopyText), puis contrôles recalculés.

    .PARAMETER Dialog
        Assistant renvoyé par Import-OpPrepareSupportWindow, avec son plan (Show-OpSupportView).

    .EXAMPLE
        Start-OpSupportCopy -Dialog $d
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject]$Dialog
    )

    $plan = $Dialog.Plan
    if (-not $PSCmdlet.ShouldProcess($plan.Destination, 'Copie sur le support')) { return }
    $c = $Dialog.Controls
    foreach ($name in 'SupportDrive', 'SupportTargets', 'SupportSources', 'BtnSupportRefresh', 'BtnSupportPrepare') { $c[$name].IsEnabled = $false }
    $c.BtnSupportClose.Content = 'Annuler'
    $c.SupportProgress.Text = 'Copie sur le support…'
    $parameters = @{ Root = $Dialog.Root; Destination = $plan.Destination; Targets = @($plan.Targets); OfficeSources = @($plan.OfficeSources) }
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpSupportCopyScript -Parameters $parameters -Confirm:$false
    $Dialog | Add-Member -NotePropertyName CopyTask -NotePropertyValue $task -Force
    [void](Register-OpBackgroundPump -Task $task -OnMessage {
            param($m, $Dialog)
            if ($m.PSObject.Properties['Kind'] -and $m.Kind -eq 'Progress') { $Dialog.Controls.SupportProgress.Text = $m.Message }
        } -OnCompleted {
            param($r, $Dialog)
            $c = $Dialog.Controls
            foreach ($name in 'SupportDrive', 'SupportTargets', 'SupportSources', 'BtnSupportRefresh') { $c[$name].IsEnabled = $true }
            $c.BtnSupportClose.Content = 'Fermer'
            if ($r.Error -or $r.Output.Count -eq 0) {
                $c.SupportProgress.Text = ''
                [void][System.Windows.MessageBox]::Show("Support non préparé : $(@($r.Error) + @($r.Errors) -join ' ')", 'OffPatch', 'OK', 'Error')
            } else {
                $text = Get-OpSupportCopyText -Result $r.Output[-1]
                $c.SupportProgress.Text = $text
                [void][System.Windows.MessageBox]::Show($text, 'OffPatch', 'OK', 'Information')
            }
            Show-OpSupportView -Dialog $Dialog
        } -Context $Dialog)
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
