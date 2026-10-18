function Invoke-OpInstallStep {
    <#
    .SYNOPSIS
        Exécute une étape du plan d'installation de ce PC (mode manuel, sans interface).

    .DESCRIPTION
        Cahier des charges 8.2 à 8.5. Le plan est recalculé (Get-OpInstallPlan) : l'étape doit y figurer à l'état
        Pending (« À installer »), sinon elle est refusée avec son état et son motif. Un contrôle préalable bloquant
        (Test-OpPreflight) refuse aussi l'étape.
        À la première étape de la session, relevé du PC et point de restauration (New-OpRestorePoint) ouvrent l'état de
        session ProgramData\OffPatch\state.json (8.6, écriture atomique), qui garde ensuite le résultat et le journal
        de chaque étape, pour la reprise et le rapport (Write-OpInstallReport).
        Exécuteur selon la catégorie : Defender (plateforme, définitions), DISM (cumulatives, checkpoint, enablement
        package, SSU, .NET), ODT (source Office). Journaux de DISM et de l'ODT dans le sous-dossier de la session.
        Les échecs (Error) de chaque étape sont comptés dans la session : au deuxième, l'étape est abandonnée et
        signalée (Abandoned), et toute nouvelle tentative est refusée ; la session continue avec les suivantes (8.6).
        Renvoie le résultat de l'exécuteur (Id, Category, State, Reason, ExitCode…), complété de StartTime, Seconds,
        RebootAfter (redémarrage prévu par le plan après cette étape), Failures et Abandoned.

    .PARAMETER StepId
        Identifiant de l'élément du manifeste, tel qu'affiché par Get-OpInstallPlan.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER Mode
        Mode noté dans state.json à l'ouverture de la session : Manual (CLI, mode manuel) ou Auto (Invoke-OpAutoSession).

    .EXAMPLE
        Invoke-OpInstallStep -StepId (Get-OpInstallPlan | Where-Object State -eq 'Pending' | Select-Object -First 1).Id
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$StepId,
        [string]$Root,
        [ValidateSet('Manual', 'Auto')][string]$Mode = 'Manual'
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    $info = Get-OpSystemInfo -Root $Root
    $blocking = @(Test-OpPreflight -Root $Root -SystemInfo $info | Where-Object { $_.Result -eq 'Blocking' })
    if ($blocking.Count -gt 0) { throw "Étape $StepId refusée, contrôle préalable bloquant : $(($blocking | ForEach-Object { "$($_.Label) : $($_.Message)" }) -join ' ; ')" }
    $plan = @(Get-OpInstallPlan -Root $Root -SystemInfo $info)
    $step = @($plan | Where-Object { $_.Id -eq $StepId }) | Select-Object -First 1
    if (-not $step) { throw "Étape $StepId absente du plan de ce PC." }
    if ($step.State -ne 'Pending') { throw "Étape $StepId non exécutée : état $($step.State) ($($step.Reason))." }
    $item = @((Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)).items | Where-Object { $_ -and $_.id -eq $StepId }) | Select-Object -First 1
    # Une étape qui a échoué deux fois dans la session est abandonnée (8.6) : plus de nouvelle tentative.
    $session = Read-OpSessionState
    $failures = 0
    $previous = $null
    if ($session) { $previous = @($session.steps | Where-Object { $_ -and $_.Id -eq $StepId }) | Select-Object -First 1 }
    if ($previous -and $previous.PSObject.Properties['Failures']) { $failures = [int]$previous.Failures }
    if ($failures -ge 2) { throw "Étape $StepId abandonnée après deux échecs dans cette session : $($previous.Reason)" }
    if (-not $PSCmdlet.ShouldProcess($StepId, "Exécution de l'étape $($step.Category)")) { return }

    if (-not $session) {
        $session = Get-OpInitialSessionState -Root $Root -SystemInfo $info -Mode $Mode -RestorePoint (New-OpRestorePoint -Configuration $configuration -Confirm:$false)
        Write-OpLog "Session $($session.sessionId) ouverte."
    }

    $logDirectory = Join-Path (Get-OpPath -Name ClientLogs) 'etapes'
    $log = Get-Variable -Name OpLog -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($log -and $log.Path) { $logDirectory = [System.IO.Path]::ChangeExtension($log.Path, $null) }
    $depot = Get-OpPath -Name Depot -Root $Root
    Write-OpLog "Étape $StepId ($($step.Category)) : début."
    $start = Get-Date
    switch ($step.Category) {
        { $_ -in 'defender-platform', 'defender' } { $result = Install-OpDefenderUpdate -Item $item -Depot $depot -Confirm:$false }
        'office-source' { $result = Install-OpOfficeUpdate -Item $item -LogDirectory $logDirectory -Root $Root -Configuration $configuration -Confirm:$false }
        default { $result = Install-OpWindowsPackage -Item $item -Depot $depot -LogDirectory $logDirectory -Confirm:$false }
    }
    $result | Add-Member -NotePropertyName StartTime -NotePropertyValue $start.ToString('o') -Force
    $result | Add-Member -NotePropertyName Seconds -NotePropertyValue ([math]::Round(((Get-Date) - $start).TotalSeconds, 1)) -Force
    $result | Add-Member -NotePropertyName RebootAfter -NotePropertyValue ([bool]$step.RebootAfter) -Force
    if ($result.State -eq 'Error') { $failures++ }
    $result | Add-Member -NotePropertyName Failures -NotePropertyValue $failures -Force
    $result | Add-Member -NotePropertyName Abandoned -NotePropertyValue ($failures -ge 2) -Force
    if ($result.Abandoned) { $result.Reason = "$($result.Reason) Étape abandonnée après deux échecs, la session continue avec les suivantes." }
    Write-OpLog "Étape $StepId : $($result.State), $($result.Reason)" -Level $(if ($result.Abandoned) { 'WARN' } else { 'INFO' })

    $session.steps = @(@($session.steps | Where-Object { $_ -and $_.Id -ne $StepId }) + $result)
    # Chaque appel de la CLI a son journal : le rapport en reprend les avertissements et les erreurs.
    $logPaths = @($session.logPaths | Where-Object { $_ })
    if ($log -and $log.Path -and $logPaths -notcontains $log.Path) { $logPaths += $log.Path }
    $session.logPaths = $logPaths
    Save-OpSessionState -State $session -Confirm:$false
    $result
}
