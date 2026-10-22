# Onglet « Journal » (cahier des charges 9, 10) : lignes du journal de tous les traitements lancés depuis la fenêtre,
# reçues par la file de messages (Add-OpJournalEntry, appelé par les onglets « Ce PC » et « Dépôt »), filtrées par
# niveau ; ouverture du dossier des journaux et du dossier des rapports dans l'Explorateur.

$script:OpJournalMaxLines = 5000
$script:OpJournalRank = @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3 }

function Test-OpJournalLevel {
    <#
    .SYNOPSIS
        Indique si une ligne de ce niveau passe le filtre de l'onglet « Journal ».

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER Level
        Niveau de la ligne (DEBUG, INFO, WARN, ERROR).

    .EXAMPLE
        Test-OpJournalLevel -Controls $ui.Controls -Level WARN
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][string]$Level
    )

    $minimum = 'DEBUG'
    if ($Controls.LogLevelFilter.SelectedItem) { $minimum = [string]$Controls.LogLevelFilter.SelectedItem.Tag }
    $rank = 0
    if ($script:OpJournalRank.ContainsKey($Level)) { $rank = $script:OpJournalRank[$Level] }
    $rank -ge $script:OpJournalRank[$minimum]
}

function Add-OpJournalEntry {
    <#
    .SYNOPSIS
        Ajoute un message de la file à l'onglet « Journal », affiché si son niveau passe le filtre.

    .DESCRIPTION
        Les messages sont gardés (5000 au plus) dans le Tag de la liste, pour réappliquer le filtre quand il change.
        Un message sans ligne de journal (avancement) est ignoré.

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .PARAMETER Message
        Message de la file (Time, Level, Message, Line).

    .EXAMPLE
        Add-OpJournalEntry -Controls $ui.Controls -Message $m
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls,
        [Parameter(Mandatory)][pscustomobject]$Message
    )

    if (-not $Message.PSObject.Properties['Line']) { return }
    $list = $Controls.LogList
    if ($null -eq $list.Tag) { $list.Tag = New-Object System.Collections.ArrayList }
    [void]$list.Tag.Add($Message)
    while ($list.Tag.Count -gt $script:OpJournalMaxLines) { $list.Tag.RemoveAt(0) }
    if (-not (Test-OpJournalLevel -Controls $Controls -Level ([string]$Message.Level))) { return }
    [void]$list.Items.Add($Message.Line)
    while ($list.Items.Count -gt $script:OpJournalMaxLines) { $list.Items.RemoveAt(0) }
    $list.ScrollIntoView($list.Items[$list.Items.Count - 1])
}

function Show-OpJournalView {
    <#
    .SYNOPSIS
        Réaffiche les lignes gardées de l'onglet « Journal » selon le niveau choisi.

    .PARAMETER Controls
        Éléments nommés de la fenêtre.

    .EXAMPLE
        Show-OpJournalView -Controls $ui.Controls
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Controls
    )

    $list = $Controls.LogList
    $list.Items.Clear()
    foreach ($m in @($list.Tag)) {
        if ($null -ne $m -and (Test-OpJournalLevel -Controls $Controls -Level ([string]$m.Level))) { [void]$list.Items.Add($m.Line) }
    }
    if ($list.Items.Count -gt 0) { $list.ScrollIntoView($list.Items[$list.Items.Count - 1]) }
}

function Get-OpLogFolder {
    <#
    .SYNOPSIS
        Renvoie le dossier des journaux à ouvrir : celui qui contient le journal le plus récent.

    .DESCRIPTION
        Deux dossiers possibles (cahier des charges 10) : logs à la racine de l'outil (face Dépôt) et
        ProgramData\OffPatch\logs (face Installation). Sans aucun journal, le premier des deux qui existe ;
        aucun : rien.

    .PARAMETER Root
        Racine de l'outil.

    .EXAMPLE
        Get-OpLogFolder -Root $ui.Root
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    # Mêmes emplacements que Get-OpPath -Name Logs et -Name ClientLogs (fonction interne du module).
    $folders = @(@((Join-Path $Root 'logs'), (Join-Path $env:ProgramData 'OffPatch\logs')) | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    if ($folders.Count -eq 0) { return }
    $latest = $folders | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.log' -File -ErrorAction SilentlyContinue } |
        Sort-Object -Property LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { return $latest.DirectoryName }
    $folders[0]
}

function Open-OpFolder {
    <#
    .SYNOPSIS
        Ouvre un dossier dans l'Explorateur ; renvoie faux s'il n'existe pas.

    .PARAMETER Path
        Dossier à ouvrir (vide : faux).

    .EXAMPLE
        if (-not (Open-OpFolder -Path $folder)) { 'Aucun journal' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()][string]$Path
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    Invoke-Item -LiteralPath $Path -ErrorAction Stop
    $true
}

function Register-OpLogTab {
    <#
    .SYNOPSIS
        Câble l'onglet « Journal » : filtre par niveau, boutons d'ouverture des dossiers.

    .PARAMETER Ui
        Fenêtre renvoyée par Import-OpMainWindow.

    .PARAMETER Root
        Racine de l'outil.

    .EXAMPLE
        Register-OpLogTab -Ui $ui -Root $root
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Ui,
        [Parameter(Mandatory)][string]$Root
    )

    $Ui | Add-Member -NotePropertyName Root -NotePropertyValue $Root -Force
    foreach ($name in 'LogLevelFilter', 'BtnOpenLogs', 'BtnOpenReports') { $Ui.Controls[$name].Tag = $Ui }
    $Ui.Controls.LogLevelFilter.Add_SelectionChanged({ Show-OpJournalView -Controls $this.Tag.Controls })
    $Ui.Controls.BtnOpenLogs.Add_Click({
            if (-not (Open-OpFolder -Path (Get-OpLogFolder -Root $this.Tag.Root))) {
                [void][System.Windows.MessageBox]::Show('Aucun journal pour l''instant.', 'OffPatch', 'OK', 'Information')
            }
        })
    $Ui.Controls.BtnOpenReports.Add_Click({
            if (-not (Open-OpFolder -Path (Join-Path $this.Tag.Root 'rapports'))) {
                [void][System.Windows.MessageBox]::Show('Aucun rapport pour l''instant.', 'OffPatch', 'OK', 'Information')
            }
        })
}
