# Onglet « Dépôt » (cahier des charges 7, 9) : résumé et fraîcheur, cibles et sources Office cochées, contenu du
# manifeste, vérification des nouveautés (-ListOnly), mise à jour, purge, annulation. Affichage et câblage
# seulement : tout passe par le module, les traitements longs dans un runspace séparé (Background.ps1).
# « Préparer un support… » est branché en phase 7.

# Inventaire du dépôt et sélection (runspace). Lecture seule.
$script:OpDepotLoadScript = {
    param([string]$Root)
    [pscustomobject]@{ Inventory = (Get-OpDepotInventory -Root $Root); Selection = (Get-OpDepotSelection -Root $Root) }
}

# Vérification (-ListOnly) ou mise à jour du dépôt (runspace), annulable par $OpCancel ; résumé dans la file.
$script:OpDepotUpdateScript = {
    param([string]$Root, [bool]$ListOnly)
    [void](Initialize-OpSession -Kind Depot -Queue $OpQueue -Root $Root)
    $r = Invoke-OpDepotUpdate -ListOnly:$ListOnly -Root $Root -CancellationToken $OpCancel -Confirm:$false
    foreach ($line in Format-OpDepotPlan -Result $r) { $OpQueue.Enqueue([pscustomobject]@{ Line = [string]$line }) }
    [pscustomobject]@{ ErrorCount = $r.ErrorCount }
}

# Purge (runspace) ; avec RemoveOrphans, les orphelins sont supprimés (confirmation déjà donnée dans l'interface).
$script:OpDepotPurgeScript = {
    param([string]$Root, [bool]$RemoveOrphans)
    [void](Initialize-OpSession -Kind Depot -Queue $OpQueue -Root $Root)
    Invoke-OpDepotPurge -Root $Root -RemoveOrphans:$RemoveOrphans -Force:$RemoveOrphans -Confirm:$false
}

function Show-OpDepotView {
    <#
    .SYNOPSIS
        Affiche dans l'onglet « Dépôt » le résumé, la sélection (cibles, sources Office) et le contenu du manifeste.

    .DESCRIPTION
        Thread de l'interface. Les cases et zones de langues sont recréées à chaque affichage ; toute modification
        active « Enregistrer la sélection ».

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER View
        Résultat de $script:OpDepotLoadScript : Inventory (Get-OpDepotInventory), Selection (Get-OpDepotSelection).

    .EXAMPLE
        Show-OpDepotView -Controls $ui.Controls -View $view
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][pscustomobject]$View
    )

    $inventory = $View.Inventory
    $text = Get-OpDepotStatusText -Status $inventory.Status
    $Controls.DepotSummary.Text = '{0} · {1} élément(s) · {2}' -f $text.Date, @($inventory.Items).Count, $inventory.TotalSize
    $Controls.DepotAlertText.Text = [string]$text.Alert
    $Controls.DepotAlert.ToolTip = $text.Detail
    $Controls.DepotAlert.Visibility = 'Collapsed'
    if ($text.Alert) { $Controls.DepotAlert.Visibility = 'Visible' }
    $Controls.DepotItems.ItemsSource = @($inventory.Items)

    $save = $Controls.BtnSaveSelection
    $Controls.DepotTargets.Children.Clear()
    foreach ($target in @($View.Selection.AvailableTargets)) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = $target
        $box.Tag = @{ Value = $target; Save = $save }
        $box.Margin = '0,2'
        $box.IsChecked = @($View.Selection.Targets) -contains $target
        $box.Add_Click({ $this.Tag.Save.IsEnabled = $true })
        [void]$Controls.DepotTargets.Children.Add($box)
    }
    $Controls.DepotSources.Children.Clear()
    foreach ($source in @($View.Selection.OfficeSources)) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,2'
        $languages = New-Object System.Windows.Controls.TextBox
        $languages.Text = @($source.Languages) -join ', '
        $languages.Width = 180
        $languages.Tag = @{ Save = $save }
        $languages.Add_TextChanged({ $this.Tag.Save.IsEnabled = $true })
        [System.Windows.Controls.DockPanel]::SetDock($languages, 'Right')
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = '{0} (canal {1})' -f $source.Id, $source.Channel
        $box.VerticalAlignment = 'Center'
        $box.IsChecked = [bool]$source.Enabled
        $box.Tag = @{ Value = $source.Id; Save = $save; Languages = $languages }
        $box.Add_Click({ $this.Tag.Save.IsEnabled = $true })
        [void]$row.Children.Add($languages)
        [void]$row.Children.Add($box)
        [void]$Controls.DepotSources.Children.Add($row)
    }
    $save.IsEnabled = $false
}

function Get-OpDepotSelectionInput {
    <#
    .SYNOPSIS
        Lit les cases et les langues saisies dans l'onglet « Dépôt », pour Set-OpDepotSelection.

    .DESCRIPTION
        Langues : séparées par des virgules, des points-virgules ou des espaces, mises en minuscules, sans doublon.
        Renvoie Targets et OfficeSources (Id, Enabled, Languages).

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .EXAMPLE
        $selection = Get-OpDepotSelectionInput -Controls $ui.Controls
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable]$Controls
    )

    $targets = @($Controls.DepotTargets.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag.Value })
    $sources = @($Controls.DepotSources.Children | ForEach-Object {
            $box = @($_.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })[0]
            $languages = @(([string]$box.Tag.Languages.Text).ToLowerInvariant() -split '[,;\s]+' | Where-Object { $_ } | Select-Object -Unique)
            [pscustomobject]@{ Id = [string]$box.Tag.Value; Enabled = [bool]$box.IsChecked; Languages = $languages }
        })
    [pscustomobject]@{ Targets = $targets; OfficeSources = $sources }
}

function Set-OpDepotBusy {
    <#
    .SYNOPSIS
        Active ou désactive les commandes de l'onglet « Dépôt » pendant un traitement.

    .DESCRIPTION
        Pendant un traitement : vérification, mise à jour, purge et sélection grisées ; Annuler actif seulement si le
        traitement l'accepte (téléchargement).

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER Busy
        Vrai pendant un traitement.

    .PARAMETER Cancellable
        Vrai si le traitement peut être annulé.

    .EXAMPLE
        Set-OpDepotBusy -Controls $ui.Controls -Busy $true -Cancellable $true
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][bool]$Busy,
        [bool]$Cancellable = $false
    )

    if (-not $PSCmdlet.ShouldProcess('onglet Dépôt', 'État des commandes')) { return }
    foreach ($name in 'BtnDepotCheck', 'BtnDepotUpdate', 'BtnDepotPurge', 'BtnPrepareSupport') { $Controls[$name].IsEnabled = -not $Busy }
    $Controls.DepotTargets.IsEnabled = -not $Busy
    $Controls.DepotSources.IsEnabled = -not $Busy
    if ($Busy) { $Controls.BtnSaveSelection.IsEnabled = $false }
    $Controls.BtnDepotCancel.IsEnabled = $Busy -and $Cancellable
}

function Invoke-OpDepotRefresh {
    <#
    .SYNOPSIS
        Relit, en arrière-plan, le contenu du dépôt et la sélection, puis met à jour l'onglet et l'en-tête.

    .PARAMETER Ui
        Fenêtre complétée de Root et ModulePath (Register-OpDepotTab).

    .EXAMPLE
        Invoke-OpDepotRefresh -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui
    )

    $task = Start-OpBackgroundTask -ScriptBlock $script:OpDepotLoadScript -Parameters @{ Root = $Ui.Root } -ModulePath $Ui.ModulePath -Confirm:$false
    [void](Register-OpBackgroundPump -Task $task -Context $Ui -OnCompleted {
            param($r, $Ui)
            if ($r.Error -or $r.Output.Count -eq 0) {
                $Ui.Controls.DepotSummary.Text = "Lecture du dépôt impossible : $(@($r.Error) + @($r.Errors) -join ' ')"
                return
            }
            Show-OpDepotView -Controls $Ui.Controls -View $r.Output[-1]
            Show-OpHeader -Controls $Ui.Controls -Status $r.Output[-1].Inventory.Status
        })
}

function Invoke-OpDepotRun {
    <#
    .SYNOPSIS
        Lance, en arrière-plan, la vérification des nouveautés (-ListOnly) ou la mise à jour du dépôt.

    .DESCRIPTION
        Cahier des charges 7.1, 9. Avancement et lignes du journal relayés dans l'onglet ; Annuler actif pendant le
        traitement ; à la fin, bilan, puis relecture du dépôt et de l'en-tête.

    .PARAMETER Ui
        Fenêtre complétée de Root et ModulePath (Register-OpDepotTab).

    .PARAMETER ListOnly
        Vérification seule : interroge le catalogue sans rien télécharger.

    .EXAMPLE
        Invoke-OpDepotRun -Ui $ui -ListOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [switch]$ListOnly
    )

    Set-OpDepotBusy -Controls $Ui.Controls -Busy $true -Cancellable $true -Confirm:$false
    $Ui.Controls.DepotCurrent.Text = 'Vérification des nouveautés…'
    if (-not $ListOnly) { $Ui.Controls.DepotCurrent.Text = 'Mise à jour du dépôt…' }
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpDepotUpdateScript -Parameters @{ Root = $Ui.Root; ListOnly = [bool]$ListOnly } -ModulePath $Ui.ModulePath -Confirm:$false
    $Ui | Add-Member -NotePropertyName DepotTask -NotePropertyValue $task -Force
    [void](Register-OpBackgroundPump -Task $task -Context $Ui -OnMessage {
            param($m, $Ui)
            if ($m.PSObject.Properties['Kind'] -and $m.Kind -eq 'Progress') { $Ui.Controls.DepotCurrent.Text = $m.Message }
            elseif ($m.PSObject.Properties['Line']) { Add-OpLogLine -ListBox $Ui.Controls.DepotLastLog -Line $m.Line; Add-OpJournalEntry -Controls $Ui.Controls -Message $m }
        } -OnCompleted {
            param($r, $Ui)
            $c = $Ui.Controls
            if ($r.Cancelled) { $c.DepotCurrent.Text = 'Annulé : le téléchargement en cours reprendra au prochain lancement.' }
            elseif ($r.Error) { $c.DepotCurrent.Text = "Échec : $($r.Error)" }
            else { $c.DepotCurrent.Text = 'Terminé : {0} erreur(s).' -f $r.Output[-1].ErrorCount }
            Set-OpDepotBusy -Controls $c -Busy $false -Confirm:$false
            Invoke-OpDepotRefresh -Ui $Ui
        })
}

function Invoke-OpDepotPurgeRun {
    <#
    .SYNOPSIS
        Purge le dépôt en arrière-plan, puis propose de supprimer les fichiers orphelins.

    .DESCRIPTION
        Cahier des charges 7.3 : les orphelins (fichiers absents du manifeste) ne sont supprimés qu'après
        confirmation ; un second passage les supprime alors.

    .PARAMETER Ui
        Fenêtre complétée de Root et ModulePath (Register-OpDepotTab).

    .PARAMETER RemoveOrphans
        Second passage, après confirmation : supprime aussi les orphelins.

    .EXAMPLE
        Invoke-OpDepotPurgeRun -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [switch]$RemoveOrphans
    )

    Set-OpDepotBusy -Controls $Ui.Controls -Busy $true -Confirm:$false
    $Ui.Controls.DepotCurrent.Text = 'Purge du dépôt…'
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpDepotPurgeScript -Parameters @{ Root = $Ui.Root; RemoveOrphans = [bool]$RemoveOrphans } -ModulePath $Ui.ModulePath -Confirm:$false
    [void](Register-OpBackgroundPump -Task $task -Context $Ui -OnMessage {
            param($m, $Ui)
            if ($m.PSObject.Properties['Line']) { Add-OpLogLine -ListBox $Ui.Controls.DepotLastLog -Line $m.Line; Add-OpJournalEntry -Controls $Ui.Controls -Message $m }
        } -OnCompleted {
            param($r, $Ui)
            $c = $Ui.Controls
            Set-OpDepotBusy -Controls $c -Busy $false -Confirm:$false
            if ($r.Error -or $r.Output.Count -eq 0) { $c.DepotCurrent.Text = "Échec de la purge : $($r.Error)" ; return }
            $p = $r.Output[-1]
            $c.DepotCurrent.Text = 'Purge terminée : {0} élément(s) retiré(s).' -f @($p.RemovedItems).Count
            $orphans = @($p.Orphans | Where-Object { $_ })
            if ($orphans.Count -gt 0 -and @($p.RemovedOrphans | Where-Object { $_ }).Count -eq 0) {
                $list = (@($orphans | Select-Object -First 10 | ForEach-Object { $_.Path }) -join [Environment]::NewLine)
                $question = "{0} fichier(s) du dépôt ne sont cités par aucun élément du manifeste :{1}{2}{1}{1}Les supprimer ?" -f $orphans.Count, [Environment]::NewLine, $list
                if ([System.Windows.MessageBox]::Show($question, 'OffPatch', 'YesNo', 'Question') -eq 'Yes') { Invoke-OpDepotPurgeRun -Ui $Ui -RemoveOrphans; return }
            }
            Invoke-OpDepotRefresh -Ui $Ui
        })
}

function Register-OpDepotTab {
    <#
    .SYNOPSIS
        Câble l'onglet « Dépôt » et lance la première lecture du dépôt.

    .PARAMETER Ui
        Fenêtre renvoyée par Import-OpMainWindow.

    .PARAMETER Root
        Racine de l'outil.

    .PARAMETER ModulePath
        Manifeste du module OffPatch, chargé par chaque runspace.

    .EXAMPLE
        Register-OpDepotTab -Ui $ui -Root $root -ModulePath $modulePath
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ModulePath
    )

    $Ui | Add-Member -NotePropertyName Root -NotePropertyValue $Root -Force
    $Ui | Add-Member -NotePropertyName ModulePath -NotePropertyValue $ModulePath -Force
    foreach ($name in 'BtnDepotCheck', 'BtnDepotUpdate', 'BtnDepotPurge', 'BtnDepotCancel', 'BtnSaveSelection', 'BtnPrepareSupport') { $Ui.Controls[$name].Tag = $Ui }
    $Ui.Controls.BtnPrepareSupport.Add_Click({ Show-OpPrepareSupport -Root $this.Tag.Root -Owner $this.Tag.Window })
    $Ui.Controls.BtnDepotCheck.Add_Click({ Invoke-OpDepotRun -Ui $this.Tag -ListOnly })
    $Ui.Controls.BtnDepotUpdate.Add_Click({ Invoke-OpDepotRun -Ui $this.Tag })
    $Ui.Controls.BtnDepotPurge.Add_Click({ Invoke-OpDepotPurgeRun -Ui $this.Tag })
    $Ui.Controls.BtnDepotCancel.Add_Click({
            $ui = $this.Tag
            if ($ui.PSObject.Properties['DepotTask'] -and $ui.DepotTask) { Stop-OpBackgroundTask -Task $ui.DepotTask -Confirm:$false }
            $this.IsEnabled = $false
            $ui.Controls.DepotCurrent.Text = 'Annulation demandée…'
        })
    $Ui.Controls.BtnSaveSelection.Add_Click({
            $ui = $this.Tag
            $selection = Get-OpDepotSelectionInput -Controls $ui.Controls
            try {
                [void](Set-OpDepotSelection -Targets $selection.Targets -OfficeSources $selection.OfficeSources -Root $ui.Root -Confirm:$false)
                Add-OpLogLine -ListBox $ui.Controls.DepotLastLog -Line 'Sélection du dépôt enregistrée.'
                Invoke-OpDepotRefresh -Ui $ui
            } catch {
                [void][System.Windows.MessageBox]::Show("Sélection non enregistrée : $($_.Exception.Message)", 'OffPatch', 'OK', 'Warning')
            }
        })
    Invoke-OpDepotRefresh -Ui $Ui
}
