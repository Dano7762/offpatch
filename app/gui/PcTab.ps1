# Onglet « Ce PC » (cahier des charges 8.7, 9) : bandeau système, contrôles préalables, étapes du plan avec cases à
# cocher, bloc Office, installation de la sélection, redémarrage, avancement et dernières lignes du journal.
# Affichage et câblage seulement : relevé, plan et installation passent par le module, dans un runspace séparé
# (Background.ps1). « Installation automatique » et « Reprendre la session interrompue » sont branchés par le
# récapitulatif du mode auto et la reprise (-Resume).

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

    $categories = @{
        'defender-platform' = 'Plateforme Defender'; 'defender' = 'Définitions Defender'; 'windows-ssu' = 'Pile de maintenance'
        'windows-checkpoint' = 'Cumulative de base (checkpoint)'; 'windows-lcu' = 'Cumulative Windows'; 'windows-ekb' = 'Passage de version (enablement package)'
        'dotnet' = '.NET Framework'; 'office-source' = 'Office'
    }
    $table = New-Object System.Data.DataTable 'Steps'
    foreach ($column in 'Id', 'Category', 'CategoryLabel', 'Detail', 'StateLabel', 'Reason') { [void]$table.Columns.Add($column, [string]) }
    foreach ($column in 'Selected', 'Pending', 'RebootAfter') { [void]$table.Columns.Add($column, [bool]) }
    foreach ($step in $Plan) {
        $row = $table.NewRow()
        $row.Id = [string]$step.Id
        $row.Category = [string]$step.Category
        $row.CategoryLabel = [string]$categories[[string]$step.Category]
        if (-not $row.CategoryLabel) { $row.CategoryLabel = [string]$step.Category }
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
}

function Add-OpPcLogLine {
    <#
    .SYNOPSIS
        Ajoute une ligne aux dernières lignes du journal de l'onglet « Ce PC » (200 au plus).

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER Line
        Ligne du journal.

    .EXAMPLE
        Add-OpPcLogLine -Controls $ui.Controls -Line $message.Line
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line
    )

    $list = $Controls.PcLastLog
    [void]$list.Items.Add($Line)
    while ($list.Items.Count -gt 200) { $list.Items.RemoveAt(0) }
    $list.ScrollIntoView($list.Items[$list.Items.Count - 1])
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
    $c.PcSystemTitle.Text = 'Relevé du PC en cours…'
    $task = Start-OpBackgroundTask -ScriptBlock $script:OpPcLoadScript -Parameters @{ Root = $Ui.Root } -ModulePath $Ui.ModulePath -Confirm:$false
    [void](Register-OpBackgroundPump -Task $task -OnMessage {
            param($m, $Ui)
            if ($m.PSObject.Properties['Line']) { Add-OpPcLogLine -Controls $Ui.Controls -Line $m.Line }
        } -OnCompleted {
            param($r, $Ui)
            if ($r.Error -or $r.Output.Count -eq 0) {
                $Ui.Controls.PcSystemTitle.Text = "Relevé du PC impossible : $($r.Error)"
                return
            }
            Show-OpPcView -Controls $Ui.Controls -View $r.Output[-1]
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
            } elseif ($m.PSObject.Properties['Line']) { Add-OpPcLogLine -Controls $Ui.Controls -Line $m.Line }
        } -OnCompleted {
            param($r, $Ui)
            $c = $Ui.Controls
            $c.PcProgress.Value = 1
            $c.PcCurrentStep.Text = 'Terminé.'
            if ($r.Error) { $c.PcCurrentStep.Text = "Interrompu : $($r.Error)" }
            elseif ($r.Output.Count -gt 0 -and $r.Output[-1].ReportPath) { Add-OpPcLogLine -Controls $c -Line "Rapport : $($r.Output[-1].ReportPath)" }
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
    $Ui.Controls.BtnRestart.Add_Click({
            $answer = [System.Windows.MessageBox]::Show('Redémarrer le PC maintenant ? Enregistrer d''abord le travail en cours.', 'OffPatch', 'YesNo', 'Question')
            if ($answer -eq 'Yes') { Restart-OpPc -Confirm:$false }
        })
    Invoke-OpPcRefresh -Ui $Ui
}
