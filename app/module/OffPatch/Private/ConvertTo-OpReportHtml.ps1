function ConvertTo-OpReportHtml {
    <#
    .SYNOPSIS
        Construit le rapport d'intervention HTML (autonome, imprimable) d'une session d'installation.

    .DESCRIPTION
        Cahier des charges 8.8. Sans effet de bord : renvoie le texte HTML. Toutes les valeurs sont échappées.
        Session attendue (champs absents tolérés) :
          - StartTime, EndTime : début et fin ; Abandoned : vrai si la session a été interrompue ;
          - Before, After : relevés de Get-OpSystemInfo au début et à la fin ;
          - Steps : une ligne par étape (Id, Category, State, Reason, ExitCode, Seconds, Installed, Available),
            plan et résultats des exécuteurs ;
          - LogPath : journaux de la session (un ou plusieurs), dont les lignes [WARN] et [ERROR] sont reprises ;
          - Offline : vrai si le PC était hors ligne en fin de session ;
          - RestorePoint : Status (Created, Existing ou None), Description, CreationTime, Reason,
            ProtectionEnabled (protection du système activée par Checkpoint-Computer) ;
          - ToolVersion, DepotDate.
        Configuration (facultative) : la recommandation de fin de support d'Office (office\sources.json).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [pscustomobject]$Configuration
    )

    function Get-Prop($Object, [string]$Name) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        $null
    }
    function ConvertTo-HtmlText([object]$Text) {
        if ($null -eq $Text -or [string]$Text -eq '') { return '&#8212;' }
        # Seuls les caractères spéciaux : HtmlEncode changerait aussi les accents en entités numériques.
        ([string]$Text).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
    }
    function Format-Date($Date) {
        if ($null -eq $Date) { return $null }
        ([datetime]$Date).ToString('dd/MM/yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    }
    function Format-Windows($Info) {
        if (-not $Info) { return $null }
        '{0} ({1}), {2}, build {3}.{4}' -f (Get-Prop $Info 'Caption'), (Get-Prop $Info 'EditionId'), (Get-Prop $Info 'DisplayVersion'), (Get-Prop $Info 'CurrentBuild'), (Get-Prop $Info 'Ubr')
    }
    function Format-Office($Office) {
        if (-not $Office) { return $null }
        '{0} ; canal {1} ; langues {2} ; version {3}' -f (@(Get-Prop $Office 'Products') -join ', '), (Get-Prop $Office 'ChannelId'), (@(Get-Prop $Office 'Languages') -join ', '), (Get-Prop $Office 'Version')
    }
    function Add-Row([System.Text.StringBuilder]$Html, [string]$Label, $Value) {
        [void]$Html.AppendLine("<tr><th>$(ConvertTo-HtmlText $Label)</th><td>$(ConvertTo-HtmlText $Value)</td></tr>")
    }
    $labels = @{ UpToDate = 'À jour'; Pending = 'À installer'; NotApplicable = 'Non applicable'; MissingFromDepot = 'Absent du dépôt'; SkippedPrerequisite = 'Ignorée (prérequis)'; Error = 'Erreur' }

    $before = Get-Prop $Session 'Before'
    $after = Get-Prop $Session 'After'
    $steps = @(Get-Prop $Session 'Steps' | Where-Object { $_ })
    $name = Get-Prop $before 'ComputerName'

    $html = New-Object System.Text.StringBuilder
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html lang="fr"><head><meta charset="utf-8">')
    [void]$html.AppendLine("<title>Rapport OffPatch $(ConvertTo-HtmlText $name)</title>")
    [void]$html.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;font-size:10pt;color:#000;background:#fff;margin:2em}h1{font-size:16pt}h2{font-size:12pt;border-bottom:1px solid #999;margin-top:1.5em}table{border-collapse:collapse;width:100%}th,td{border:1px solid #bbb;padding:3px 6px;text-align:left;vertical-align:top}th{background:#eee;width:28%}table.steps th{width:auto}.Error{color:#a00;font-weight:bold}.UpToDate{color:#060}.note{background:#fff6d5;border:1px solid #d9b500;padding:6px;margin:6px 0}@media print{body{margin:0}h2{page-break-after:avoid}tr{page-break-inside:avoid}}</style>')
    [void]$html.AppendLine('</head><body>')
    [void]$html.AppendLine("<h1>Rapport d'intervention OffPatch</h1>")
    if (Get-Prop $Session 'Abandoned') { [void]$html.AppendLine('<p class="note">Session interrompue avant la fin.</p>') }

    [void]$html.AppendLine('<h2>Session</h2><table>')
    Add-Row $html 'Début' (Format-Date (Get-Prop $Session 'StartTime'))
    Add-Row $html 'Fin' (Format-Date (Get-Prop $Session 'EndTime'))
    Add-Row $html 'Version de l''outil' (Get-Prop $Session 'ToolVersion')
    Add-Row $html 'Date du dépôt' (Get-Prop $Session 'DepotDate')
    [void]$html.AppendLine('</table>')

    [void]$html.AppendLine('<h2>Poste</h2><table>')
    Add-Row $html 'Nom du PC' $name
    Add-Row $html 'Fabricant' (Get-Prop $before 'Manufacturer')
    Add-Row $html 'Modèle' (Get-Prop $before 'Model')
    Add-Row $html 'Numéro de série (BIOS)' (Get-Prop $before 'SerialNumber')
    Add-Row $html 'Windows avant' (Format-Windows $before)
    Add-Row $html 'Windows après' (Format-Windows $after)
    $esu = Get-Prop $before 'Esu'
    if ($esu) {
        $esuText = [string](Get-Prop $esu 'Status')
        if (Get-Prop $esu 'Year') { $esuText += " (année $(Get-Prop $esu 'Year'))" }
        if (Get-Prop $esu 'Detail') { $esuText += " : $(Get-Prop $esu 'Detail')" }
        Add-Row $html 'ESU (Windows 10)' $esuText
    }
    [void]$html.AppendLine('</table>')

    [void]$html.AppendLine('<h2>Defender</h2><table>')
    foreach ($pair in @(@('defender-platform', 'Plateforme'), @('defender', 'Définitions'))) {
        $step = @($steps | Where-Object { (Get-Prop $_ 'Category') -eq $pair[0] }) | Select-Object -First 1
        $text = $null
        if ($step -and (Get-Prop $step 'State') -eq 'UpToDate') { $text = "Version $(Get-Prop $step 'Installed')" }
        elseif ($step) { $text = "$($labels[[string](Get-Prop $step 'State')]) : $(Get-Prop $step 'Reason')" }
        Add-Row $html $pair[1] $text
    }
    [void]$html.AppendLine('</table><p>Defender se met à jour seul dès que le PC est connecté à Internet.</p>')

    [void]$html.AppendLine('<h2>Office</h2><table>')
    Add-Row $html 'Office détecté (avant)' (Format-Office (Get-Prop $before 'Office'))
    Add-Row $html 'Office après' (Format-Office (Get-Prop $after 'Office'))
    $officeStep = @($steps | Where-Object { (Get-Prop $_ 'Category') -eq 'office-source' }) | Select-Object -First 1
    if ($officeStep -and (Get-Prop $officeStep 'State') -ne 'UpToDate') {
        Add-Row $html 'Motif' "$($labels[[string](Get-Prop $officeStep 'State')]) : $(Get-Prop $officeStep 'Reason')"
        $endOfSupport = Get-Prop (Get-Prop $Configuration 'OfficeSources') 'endOfSupport'
        if ($endOfSupport -and [string](Get-Prop $officeStep 'Reason') -like "*$(Get-Prop $endOfSupport 'reason')*") { Add-Row $html 'Recommandation' (Get-Prop $endOfSupport 'recommendation') }
    }
    [void]$html.AppendLine('</table>')

    [void]$html.AppendLine('<h2>Étapes</h2><table class="steps"><tr><th>#</th><th>Catégorie</th><th>Élément</th><th>Résultat</th><th>Code retour</th><th>Durée</th><th>Détail</th></tr>')
    $n = 0
    foreach ($step in $steps) {
        $n++
        $state = [string](Get-Prop $step 'State')
        $label = $labels[$state]
        if (-not $label) { $label = $state }
        $seconds = Get-Prop $step 'Seconds'
        $duration = $null
        if ($null -ne $seconds) { $duration = '{0} s' -f [math]::Round([double]$seconds) }
        $cells = @($n, (Get-Prop $step 'Category'), (Get-Prop $step 'Id'), $label, (Get-Prop $step 'ExitCode'), $duration, (Get-Prop $step 'Reason')) | ForEach-Object { "<td>$(ConvertTo-HtmlText $_)</td>" }
        [void]$html.AppendLine("<tr class=`"$(ConvertTo-HtmlText $state)`">$($cells -join '')</tr>")
    }
    [void]$html.AppendLine('</table>')

    [void]$html.AppendLine('<h2>Erreurs et avertissements</h2>')
    $issues = @(foreach ($logPath in @(Get-Prop $Session 'LogPath' | Where-Object { $_ })) {
            if (Test-Path -LiteralPath $logPath -PathType Leaf) { Get-Content -LiteralPath $logPath -Encoding UTF8 | Where-Object { $_ -match '\[(WARN|ERROR)\]' } }
        })
    if ($issues.Count -eq 0) { [void]$html.AppendLine('<p>Aucun.</p>') }
    else { [void]$html.AppendLine("<ul>$(($issues | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join '')</ul>") }

    if (Get-Prop $Session 'Offline') { [void]$html.AppendLine('<p class="note">Le PC était hors ligne en fin de session : désactiver le mode Avion ou rebrancher le réseau, pour que Windows et Defender se mettent à jour d''eux-mêmes.</p>') }

    [void]$html.AppendLine('<h2>Point de restauration</h2><table>')
    $restore = Get-Prop $Session 'RestorePoint'
    switch ([string](Get-Prop $restore 'Status')) {
        'Created' { Add-Row $html 'Point créé par OffPatch' "$(Get-Prop $restore 'Description') ($(Format-Date (Get-Prop $restore 'CreationTime')))" }
        'Existing' { Add-Row $html 'Point existant de moins de 24 heures' "$(Get-Prop $restore 'Description') ($(Format-Date (Get-Prop $restore 'CreationTime')))" }
        default { Add-Row $html 'Aucun point' (Get-Prop $restore 'Reason') }
    }
    if (Get-Prop $restore 'ProtectionEnabled') { Add-Row $html 'Remarque' 'Protection du système activée par Checkpoint-Computer, à vérifier.' }
    [void]$html.AppendLine('</table>')

    [void]$html.AppendLine('</body></html>')
    $html.ToString()
}
