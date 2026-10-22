# Onglet « Ce PC » (cahier des charges 8.7, 9) : bandeau système, contrôles préalables, étapes du plan avec cases à
# cocher, bloc Office, installation de la sélection, redémarrage, avancement et dernières lignes du journal.
# Affichage et câblage seulement : relevé, plan et installation passent par le module, dans un runspace séparé
# (Background.ps1). « Installation automatique » passe par le récapitulatif (Dialogs/AutoSummary.ps1) ;
# « Reprendre la session interrompue » est branché par la reprise (-Resume).

# Relevé du PC, contrôles préalables et plan (runspace). Lecture seule.
$script:OpPcLoadScript = {
    param([string]$Root)
    $context = Initialize-OpSession -Kind Session -Queue $OpQueue -Root $Root
    $info = Get-OpSystemInfo -Root $Root
    [pscustomobject]@{
        Info          = $info
        Checks        = @(Test-OpPreflight -Root $Root -SystemInfo $info)
        Plan          = @(Get-OpInstallPlan -Root $Root -SystemInfo $info)
        OfficeSources = $context.Configuration.OfficeSources
    }
}

# Étapes cochées, dans l'ordre du plan (runspace). Arrêt après une étape réussie qui demande un redémarrage : les
# suivantes attendent le redémarrage (8.7). Puis rapport et fin de session ; au lancement suivant, l'outil refait
# simplement la détection.
$script:OpPcInstallScript = {
    param([string]$Root, [string[]]$Ids)
    [void](Initialize-OpSession -Kind Session -Queue $OpQueue -Root $Root)
    $results = @()
    for ($i = 0; $i -lt $Ids.Count; $i++) {
        $OpQueue.Enqueue([pscustomobject]@{ Kind = 'Step'; Index = $i; Count = $Ids.Count; Id = $Ids[$i] })
        try {
            $r = Invoke-OpInstallStep -StepId $Ids[$i] -Root $Root -Confirm:$false
            $results += $r
            if ($r.State -ne 'Error' -and $r.RebootAfter) { break }
        } catch {
            $message = "Étape $($Ids[$i]) non exécutée : $($_.Exception.Message)"
            $OpQueue.Enqueue([pscustomobject]@{ Level = 'ERROR'; Message = $message; Line = ('{0:yyyy-MM-dd HH:mm:ss} [ERROR] {1}' -f (Get-Date), $message) })
            $results += [pscustomobject]@{ Id = $Ids[$i]; State = 'Error'; Reason = $_.Exception.Message }
        }
    }
    [pscustomobject]@{ Results = $results; ReportPath = (Write-OpInstallReport -Root $Root -Confirm:$false -WarningAction SilentlyContinue) }
}

# Session automatique validée au récapitulatif (runspace, 8.6) : plus aucune question. Étapes et compte à rebours
# déposés dans la file ; le redémarrage s'annule par $OpCancel (bouton « Annuler le redémarrage »).
$script:OpPcAutoScript = {
    param([string]$Root, [bool]$ForceWindows)
    [void](Initialize-OpSession -Kind Session -Queue $OpQueue -Root $Root)
    $onStep = { param($s) $OpQueue.Enqueue([pscustomobject]@{ Kind = 'AutoStep'; Id = $s.Id; Done = [bool]$s.PSObject.Properties['Seconds']; State = $s.State }) }
    $onTick = { param($left) $OpQueue.Enqueue([pscustomobject]@{ Kind = 'Countdown'; Seconds = $left }) }
    Invoke-OpAutoSession -Root $Root -ForceWindows:$ForceWindows -OnStep $onStep -OnTick $onTick -IsCancelled { $OpCancel.IsCancellationRequested } -Confirm:$false
}

function ConvertTo-OpPcStepTable {
    <#
    .SYNOPSIS
        Convertit le plan en table pour le tableau des étapes (liaison WPF, cases à cocher).

    .DESCRIPTION
        Une ligne par étape du plan, dans son ordre. Les étapes à installer sont cochées par défaut ; les autres ne
        peuvent pas l'être (Pending faux). Detail : version ou KB disponible, sinon l'identifiant.

    .PARAMETER Plan
        Lignes de Get-OpInstallPlan.

    .EXAMPLE
        $grid.ItemsSource = (ConvertTo-OpPcStepTable -Plan $plan).DefaultView
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [AllowEmptyCollection()][object[]]$Plan = @()
    )

    $table = New-Object System.Data.DataTable 'Steps'
    foreach ($column in 'Id', 'Category', 'CategoryLabel', 'Detail', 'StateLabel', 'Reason') { [void]$table.Columns.Add($column, [string]) }
    foreach ($column in 'Selected', 'Pending', 'RebootAfter') { [void]$table.Columns.Add($column, [bool]) }
    foreach ($step in $Plan) {
        $row = $table.NewRow()
        $row.Id = [string]$step.Id
        $row.Category = [string]$step.Category
        $row.CategoryLabel = [string]$step.CategoryLabel
        $row.Detail = [string]$step.Available
        if (-not $row.Detail) { $row.Detail = [string]$step.Id }
        $row.StateLabel = [string]$step.StateLabel
        $row.Reason = [string]$step.Reason
        $row.Pending = $step.State -eq 'Pending' -and [bool]$step.Id
        $row.Selected = $row.Pending
        $row.RebootAfter = [bool]$step.RebootAfter
        $table.Rows.Add($row)
    }
    , $table
}

function Get-OpPcSummary {
    <#
    .SYNOPSIS
        Prépare les textes de l'onglet « Ce PC » à partir du relevé, des contrôles et du plan.

    .DESCRIPTION
        Sans WPF (testable) : titre et détail du bandeau système, contrôles préalables qui ne sont pas Ok, bloc Office
        (Office détecté, source du dépôt et ses langues, ou motif de non-application), redémarrage en attente,
        installation possible (une étape à installer et aucun contrôle bloquant).

    .PARAMETER View
        Résultat du relevé ($script:OpPcLoadScript) : Info, Checks, Plan, OfficeSources.

    .EXAMPLE
        (Get-OpPcSummary -View $view).Title
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$View
    )

    $i = $View.Info
    $title = '{0} — {1} {2}, build {3}.{4}, {5}' -f $i.ComputerName, $i.Caption, $i.DisplayVersion, $i.CurrentBuild, $i.Ubr, $i.Architecture
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("Fabricant : $($i.Manufacturer)")
    $parts.Add("Modèle : $($i.Model)")
    $parts.Add("N° de série : $($i.SerialNumber)")
    if ($null -ne $i.FreeSpaceBytes) { $parts.Add(('Espace libre sur {0} : {1:N1} Go' -f $i.SystemDrive, ($i.FreeSpaceBytes / 1GB))) }
    if (-not $i.Power) { $parts.Add('Alimentation : illisible') }
    elseif ($i.Power.OnBattery) { $parts.Add("Alimentation : batterie ($($i.Power.BatteryPercent) %)") }
    else { $parts.Add('Alimentation : secteur') }
    if ($i.Family -eq 'Windows10') {
        if ($i.Esu -and $i.Esu.Status -eq 'Active') { $parts.Add("ESU : actif (année $($i.Esu.Year))") } else { $parts.Add('ESU : absent ou indétectable') }
    }

    $checks = @($View.Checks | Where-Object { $_.Result -ne 'Ok' } | ForEach-Object {
            $prefix = ''
            if ($_.Result -eq 'Blocking') { $prefix = 'Bloquant — ' }
            "$prefix$($_.Label) : $($_.Message)"
        })

    $office = 'Office : aucun Office Click-to-Run.'
    $step = @($View.Plan | Where-Object { $_.Category -eq 'office-source' }) | Select-Object -First 1
    if ($i.Office) {
        $o = $i.Office
        $source = $null
        if ($View.OfficeSources) { $source = @($View.OfficeSources.sources | Where-Object { @($_.installedChannelIds) -contains $o.ChannelId }) | Select-Object -First 1 }
        $channel = $o.ChannelId
        if ($source) { $channel = $source.channel }
        $office = 'Office : {0}, canal {1}, langues {2}, version {3}.' -f (@($o.Products) -join ', '), $channel, (@($o.Languages) -join ', '), $o.Version
        if ($source) { $office += ' Source du dépôt : {0} ({1}).' -f $source.id, (@($source.languages) -join ', ') }
    }
    if ($step) { $office += ' {0} : {1}' -f $step.StateLabel, $step.Reason }

    $reboot = @($View.Checks | Where-Object { $_.Id -eq 'PendingReboot' -and $_.Result -ne 'Ok' }).Count -gt 0
    $blocking = @($View.Checks | Where-Object { $_.Result -eq 'Blocking' }).Count -gt 0
    $pending = @($View.Plan | Where-Object { $_.State -eq 'Pending' -and $_.Id }).Count -gt 0
    [pscustomobject]@{
        Title = $title; Detail = ($parts -join ' · '); Checks = $checks; Office = $office
        RebootPending = $reboot; CanInstall = $pending -and -not $blocking
    }
}

function Show-OpPcView {
    <#
    .SYNOPSIS
        Affiche dans l'onglet « Ce PC » le relevé, les contrôles, le plan et le bloc Office.

    .DESCRIPTION
        Thread de l'interface. Le tableau des étapes est lié à une DataTable (cases à cocher en liaison bidirectionnelle).

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER View
        Résultat du relevé ($script:OpPcLoadScript).

    .EXAMPLE
        Show-OpPcView -Controls $ui.Controls -View $view
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][pscustomobject]$View
    )

    $summary = Get-OpPcSummary -View $View
    $Controls.PcSystemTitle.Text = $summary.Title
    $Controls.PcSystemDetail.Text = $summary.Detail
    $Controls.PcChecksText.Text = ($summary.Checks -join [Environment]::NewLine)
    $Controls.PcChecks.Visibility = 'Collapsed'
    if ($summary.Checks.Count -gt 0) { $Controls.PcChecks.Visibility = 'Visible' }
    $Controls.PcRebootBanner.Visibility = 'Collapsed'
    if ($summary.RebootPending) { $Controls.PcRebootBanner.Visibility = 'Visible' }
    $Controls.PcSteps.ItemsSource = (ConvertTo-OpPcStepTable -Plan $View.Plan).DefaultView
    $Controls.PcOfficeText.Text = $summary.Office
    $Controls.BtnInstallSelection.IsEnabled = $summary.CanInstall
    $Controls.BtnAuto.IsEnabled = $summary.CanInstall
}

function Invoke-OpPcRefresh {
    <#
    .SYNOPSIS
        Relance, en arrière-plan, le relevé du PC et le plan, puis met l'onglet à jour.

    .PARAMETER Ui
        Fenêtre (Import-OpMainWindow) complétée de Root et ModulePath (Register-OpPcTab).

    .EXAMPLE
        Invoke-OpPcRefresh -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui
    )

    $c = $Ui.Controls
    $c.BtnInstallSelection.IsEnabled = $false
    $c.BtnAuto.IsEnabled = $false
    $c.PcSystemTitle.Text = 'Relevé du PC en cours…'
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpPcLoadScript -Parameters @{ Root = $Ui.Root } -ModulePath $Ui.ModulePath -Confirm:$false
    [void](Register-OpBackgroundPump -Task $task -OnMessage {
            param($m, $Ui)
            if ($m.PSObject.Properties['Line']) { Add-OpLogLine -ListBox $Ui.Controls.PcLastLog -Line $m.Line; Add-OpJournalEntry -Controls $Ui.Controls -Message $m }
        } -OnCompleted {
            param($r, $Ui)
            if ($r.Error -or $r.Output.Count -eq 0) {
                $Ui.Controls.PcSystemTitle.Text = "Relevé du PC impossible : $(@($r.Error) + @($r.Errors) -join ' ')"
                return
            }
            # Relevé gardé pour le récapitulatif du mode automatique.
            $Ui | Add-Member -NotePropertyName PcView -NotePropertyValue $r.Output[-1] -Force
            Show-OpPcView -Controls $Ui.Controls -View $r.Output[-1]
        } -Context $Ui)
}

function Invoke-OpPcAuto {
    <#
    .SYNOPSIS
        Affiche le récapitulatif du mode automatique, puis, s'il est validé, lance la session en arrière-plan.

    .DESCRIPTION
        Cahier des charges 8.6. Une seule validation (Show-OpAutoSummary), avec le forçage éventuel pour Windows 10
        sans ESU ; ensuite Invoke-OpAutoSession sans confirmation. Boutons en conflit désactivés, étape en cours
        affichée, compte à rebours avant redémarrage avec « Annuler le redémarrage ». Redémarrage annulé ou session
        terminée : détection refaite.

    .PARAMETER Ui
        Fenêtre complétée de Root, ModulePath (Register-OpPcTab) et PcView (Invoke-OpPcRefresh).

    .EXAMPLE
        Invoke-OpPcAuto -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui
    )

    if (-not $Ui.PSObject.Properties['PcView'] -or -not $Ui.PcView) { return }
    $choice = Show-OpAutoSummary -View $Ui.PcView -Owner $Ui.Window
    if (-not $choice) { return }
    $c = $Ui.Controls
    foreach ($button in 'BtnInstallSelection', 'BtnAuto', 'BtnRestart', 'BtnResume') { $c[$button].IsEnabled = $false }
    $c.PcSteps.IsEnabled = $false
    $c.PcProgress.IsIndeterminate = $true
    $c.PcCurrentStep.Text = 'Session automatique en cours…'
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpPcAutoScript -Parameters @{ Root = $Ui.Root; ForceWindows = $choice.ForceWindows } -ModulePath $Ui.ModulePath -Confirm:$false
    $Ui | Add-Member -NotePropertyName AutoTask -NotePropertyValue $task -Force
    [void](Register-OpBackgroundPump -Task $task -OnMessage {
            param($m, $Ui)
            $c = $Ui.Controls
            if ($m.PSObject.Properties['Kind'] -and $m.Kind -eq 'AutoStep') {
                $c.PcCurrentStep.Text = "Étape $($m.Id) : en cours…"
                if ($m.Done -and $m.State -eq 'Error') { $c.PcCurrentStep.Text = "Étape $($m.Id) : en erreur." }
                elseif ($m.Done) { $c.PcCurrentStep.Text = "Étape $($m.Id) : terminée." }
            } elseif ($m.PSObject.Properties['Kind'] -and $m.Kind -eq 'Countdown') {
                $c.PcCurrentStep.Text = "Redémarrage dans $($m.Seconds) s"
                if (-not $Ui.AutoTask.Cancellation.IsCancellationRequested) { $c.BtnCancelReboot.Visibility = 'Visible' }
            } elseif ($m.PSObject.Properties['Line']) { Add-OpLogLine -ListBox $c.PcLastLog -Line $m.Line; Add-OpJournalEntry -Controls $c -Message $m }
        } -OnCompleted {
            param($r, $Ui)
            $c = $Ui.Controls
            $c.PcProgress.IsIndeterminate = $false
            $c.BtnCancelReboot.Visibility = 'Collapsed'
            $result = $null
            if ($r.Output.Count -gt 0) { $result = $r.Output[-1] }
            if ($r.Error) { $c.PcCurrentStep.Text = "Session automatique interrompue : $($r.Error)" }
            elseif (-not $result) { $c.PcCurrentStep.Text = 'Session automatique non démarrée.' }
            elseif ($result.Result -eq 'Restarting') {
                $c.PcCurrentStep.Text = 'Redémarrage du PC : la session reprendra à l''ouverture de session.'
                return
            } elseif ($result.Result -eq 'Cancelled') { $c.PcCurrentStep.Text = 'Redémarrage annulé : état de la session conservé, à reprendre plus tard.' }
            else {
                $c.PcProgress.Value = 1
                $c.PcCurrentStep.Text = 'Session automatique terminée.'
                if ($result.ReportPath) { Add-OpLogLine -ListBox $c.PcLastLog -Line "Rapport : $($result.ReportPath)" }
            }
            foreach ($button in 'BtnRestart', 'BtnResume') { $c[$button].IsEnabled = $true }
            $c.PcSteps.IsEnabled = $true
            Invoke-OpPcRefresh -Ui $Ui
        } -Context $Ui)
}

function Invoke-OpPcInstall {
    <#
    .SYNOPSIS
        Installe, en arrière-plan, les étapes cochées dans l'ordre du plan, puis relance la détection.

    .DESCRIPTION
        Cahier des charges 8.7. Boutons en conflit désactivés pendant le traitement ; avancement par étape ; arrêt
        après une étape qui demande un redémarrage (bandeau « Redémarrer maintenant » ensuite) ; rapport écrit.

    .PARAMETER Ui
        Fenêtre complétée de Root et ModulePath (Register-OpPcTab).

    .EXAMPLE
        Invoke-OpPcInstall -Ui $ui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui
    )

    $c = $Ui.Controls
    $ids = @($c.PcSteps.ItemsSource | Where-Object { $_.Pending -and $_.Selected } | ForEach-Object { [string]$_.Id })
    if ($ids.Count -eq 0) { return }
    foreach ($button in 'BtnInstallSelection', 'BtnAuto', 'BtnRestart', 'BtnResume') { $c[$button].IsEnabled = $false }
    $c.PcSteps.IsEnabled = $false
    $c.PcProgress.Value = 0
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpPcInstallScript -Parameters @{ Root = $Ui.Root; Ids = $ids } -ModulePath $Ui.ModulePath -Confirm:$false
    [void](Register-OpBackgroundPump -Task $task -OnMessage {
            param($m, $Ui)
            if ($m.PSObject.Properties['Kind'] -and $m.Kind -eq 'Step') {
                $Ui.Controls.PcCurrentStep.Text = 'Étape {0}/{1} : {2}' -f ($m.Index + 1), $m.Count, $m.Id
                $Ui.Controls.PcProgress.Value = $m.Index / $m.Count
            } elseif ($m.PSObject.Properties['Line']) { Add-OpLogLine -ListBox $Ui.Controls.PcLastLog -Line $m.Line; Add-OpJournalEntry -Controls $Ui.Controls -Message $m }
        } -OnCompleted {
            param($r, $Ui)
            $c = $Ui.Controls
            $c.PcProgress.Value = 1
            $c.PcCurrentStep.Text = 'Terminé.'
            if ($r.Error) { $c.PcCurrentStep.Text = "Interrompu : $($r.Error)" }
            elseif ($r.Output.Count -gt 0 -and $r.Output[-1].ReportPath) { Add-OpLogLine -ListBox $c.PcLastLog -Line "Rapport : $($r.Output[-1].ReportPath)" }
            foreach ($button in 'BtnRestart', 'BtnResume') { $c[$button].IsEnabled = $true }
            $c.PcSteps.IsEnabled = $true
            Invoke-OpPcRefresh -Ui $Ui
        } -Context $Ui)
}

function Restart-OpPc {
    <#
    .SYNOPSIS
        Redémarre le PC tout de suite (bouton « Redémarrer maintenant », mode manuel).

    .DESCRIPTION
        Cahier des charges 8.7 : aucune tâche planifiée en mode manuel ; au lancement suivant, l'outil refait la
        détection. La confirmation est demandée par l'interface avant l'appel.

    .EXAMPLE
        Restart-OpPc -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Redémarrage immédiat')) { Restart-Computer -Force }
}

function Register-OpPcTab {
    <#
    .SYNOPSIS
        Câble l'onglet « Ce PC » et lance le premier relevé.

    .DESCRIPTION
        Complète la fenêtre de Root et ModulePath, branche « Installer la sélection » et « Redémarrer maintenant »
        (confirmation par une boîte de dialogue), puis lance le relevé en arrière-plan.

    .PARAMETER Ui
        Fenêtre renvoyée par Import-OpMainWindow.

    .PARAMETER Root
        Racine de l'outil.

    .PARAMETER ModulePath
        Manifeste du module OffPatch, chargé par chaque runspace.

    .EXAMPLE
        Register-OpPcTab -Ui $ui -Root $root -ModulePath $modulePath
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ModulePath
    )

    $Ui | Add-Member -NotePropertyName Root -NotePropertyValue $Root -Force
    $Ui | Add-Member -NotePropertyName ModulePath -NotePropertyValue $ModulePath -Force
    $Ui.Controls.BtnInstallSelection.Tag = $Ui
    $Ui.Controls.BtnInstallSelection.Add_Click({ Invoke-OpPcInstall -Ui $this.Tag })
    $Ui.Controls.BtnAuto.Tag = $Ui
    $Ui.Controls.BtnAuto.Add_Click({ Invoke-OpPcAuto -Ui $this.Tag })
    $Ui.Controls.BtnCancelReboot.Tag = $Ui
    $Ui.Controls.BtnCancelReboot.Add_Click({
            $ui = $this.Tag
            if ($ui.PSObject.Properties['AutoTask'] -and $ui.AutoTask) { Stop-OpBackgroundTask -Task $ui.AutoTask -Confirm:$false }
            $this.Visibility = 'Collapsed'
            $ui.Controls.PcCurrentStep.Text = 'Annulation du redémarrage demandée…'
        })
    $Ui.Controls.BtnRestart.Add_Click({
            $answer = [System.Windows.MessageBox]::Show('Redémarrer le PC maintenant ? Enregistrer d''abord le travail en cours.', 'OffPatch', 'YesNo', 'Question')
            if ($answer -eq 'Yes') { Restart-OpPc -Confirm:$false }
        })
    Invoke-OpPcRefresh -Ui $Ui
}
