# Récapitulatif du mode automatique (cahier des charges 8.6) : étapes prévues, Office, avertissements (dont le rappel du
# mode Avion et la batterie, 8.2), forçage Windows 10 sans ESU. Une seule validation, puis plus aucune question.
# Affichage seulement : le relevé vient de l'onglet « Ce PC » (PcTab.ps1), la session de Invoke-OpAutoSession.

function Get-OpAutoSummary {
    <#
    .SYNOPSIS
        Prépare les textes du récapitulatif du mode automatique à partir du relevé de l'onglet « Ce PC ».

    .DESCRIPTION
        Sans WPF (testable). Steps : une ligne par étape à installer, dans l'ordre du plan, avec le redémarrage qui
        la suit ; sous Windows 10 sans ESU (contrôle préalable SkipWindowsInAuto), les étapes Windows et .NET sont
        marquées « ignorée sauf forçage » (R-04, R-19). Office : bloc Office de l'onglet (canal, source ou motif).
        Warnings : contrôles en avertissement (réseau et mode Avion, batterie, ESU…). CanForceWindows : forçage
        proposé. CanStart : une étape à installer et aucun contrôle bloquant.

    .PARAMETER View
        Relevé de l'onglet « Ce PC » : Info, Checks, Plan, OfficeSources.

    .EXAMPLE
        (Get-OpAutoSummary -View $view).Steps
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$View
    )

    $pc = Get-OpPcSummary -View $View
    $canForce = @($View.Checks | Where-Object { $_.PSObject.Properties['Action'] -and $_.Action -eq 'SkipWindowsInAuto' }).Count -gt 0
    $steps = @($View.Plan | Where-Object { $_.State -eq 'Pending' -and $_.Id } | ForEach-Object {
            $detail = [string]$_.Available
            if (-not $detail) { $detail = [string]$_.Id }
            $line = "$($_.CategoryLabel) : $detail"
            if ($_.RebootAfter) { $line += ' — redémarrage ensuite' }
            if ($canForce -and ($_.Category -like 'windows-*' -or $_.Category -eq 'dotnet')) { $line += ' — ignorée sauf forçage (ESU absent)' }
            $line
        })
    $warnings = @($View.Checks | Where-Object { $_.Result -eq 'Warning' } | ForEach-Object { "$($_.Label) : $($_.Message)" })
    [pscustomobject]@{ Steps = $steps; Office = $pc.Office; Warnings = $warnings; CanForceWindows = $canForce; CanStart = $pc.CanInstall }
}

function Import-OpAutoSummaryWindow {
    <#
    .SYNOPSIS
        Charge et remplit la fenêtre du récapitulatif, sans l'afficher.

    .DESCRIPTION
        AutoSummary.xaml par Import-OpMainWindow -Path. « Démarrer » n'est actif que si la session peut démarrer ; la
        case de forçage n'apparaît que sous Windows 10 sans ESU, décochée. Thread STA requis.

    .PARAMETER View
        Relevé de l'onglet « Ce PC ».

    .EXAMPLE
        $d = Import-OpAutoSummaryWindow -View $view; [void]$d.Window.ShowDialog()
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$View
    )

    $summary = Get-OpAutoSummary -View $View
    $d = Import-OpMainWindow -Path (Join-Path $PSScriptRoot 'AutoSummary.xaml')
    $c = $d.Controls
    foreach ($line in $summary.Steps) { [void]$c.SummarySteps.Items.Add($line) }
    if ($summary.Steps.Count -eq 0) { [void]$c.SummarySteps.Items.Add('Aucune étape à installer.') }
    $c.SummaryOffice.Text = $summary.Office
    if ($summary.Warnings.Count -gt 0) {
        $c.SummaryWarningsText.Text = $summary.Warnings -join [Environment]::NewLine
        $c.SummaryWarnings.Visibility = 'Visible'
    }
    if ($summary.CanForceWindows) { $c.SummaryForceWindows.Visibility = 'Visible' }
    $c.BtnSummaryStart.IsEnabled = $summary.CanStart
    $c.BtnSummaryStart.Tag = $d.Window
    $c.BtnSummaryStart.Add_Click({ $this.Tag.DialogResult = $true })
    $d
}

function Show-OpAutoSummary {
    <#
    .SYNOPSIS
        Affiche le récapitulatif du mode automatique et renvoie la décision.

    .DESCRIPTION
        Fenêtre modale. Validée : renvoie ForceWindows (case de forçage cochée). Annulée ou fermée : rien.

    .PARAMETER View
        Relevé de l'onglet « Ce PC ».

    .PARAMETER Owner
        Fenêtre principale (centrage, modalité).

    .EXAMPLE
        $choice = Show-OpAutoSummary -View $ui.PcView -Owner $ui.Window
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$View,
        [System.Windows.Window]$Owner
    )

    $d = Import-OpAutoSummaryWindow -View $View
    if ($Owner) { $d.Window.Owner = $Owner }
    if (-not $d.Window.ShowDialog()) { return }
    [pscustomobject]@{ ForceWindows = [bool]$d.Controls.SummaryForceWindows.IsChecked }
}
