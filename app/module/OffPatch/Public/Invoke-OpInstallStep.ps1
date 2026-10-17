function Invoke-OpInstallStep {
    <#
    .SYNOPSIS
        Exécute une étape du plan d'installation de ce PC (mode manuel, sans interface).

    .DESCRIPTION
        Cahier des charges 8.2 à 8.5. Le plan est recalculé (Get-OpInstallPlan) : l'étape doit y figurer à l'état
        Pending (« À installer »), sinon elle est refusée avec son état et son motif. Un contrôle préalable bloquant
        (Test-OpPreflight) refuse aussi l'étape.
        À la première étape de la session, relevé du PC et point de restauration (New-OpRestorePoint) sont gardés
        dans ProgramData\OffPatch\temp\cli-session.json, avec le résultat et le journal de chaque étape, pour le rapport
        (Write-OpInstallReport). Écriture atomique.
        Exécuteur selon la catégorie : Defender (plateforme, définitions), DISM (cumulatives, checkpoint, enablement
        package, SSU, .NET), ODT (source Office). Journaux de DISM et de l'ODT dans le sous-dossier de la session.
        Renvoie le résultat de l'exécuteur (Id, Category, State, Reason, ExitCode…), complété de StartTime, Seconds
        et RebootAfter (redémarrage prévu par le plan après cette étape).

    .PARAMETER StepId
        Identifiant de l'élément du manifeste, tel qu'affiché par Get-OpInstallPlan.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Invoke-OpInstallStep -StepId (Get-OpInstallPlan | Where-Object State -eq 'Pending' | Select-Object -First 1).Id
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$StepId,
        [string]$Root
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
    if (-not $PSCmdlet.ShouldProcess($StepId, "Exécution de l'étape $($step.Category)")) { return }

    $sessionPath = Join-Path (Get-OpPath -Name ClientTemp) 'cli-session.json'
    $session = $null
    if (Test-Path -LiteralPath $sessionPath -PathType Leaf) { $session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    if (-not $session) {
        # Versions et dates en texte : ConvertTo-Json de PowerShell 5.1 en ferait des objets.
        if ($info.PSObject.Properties['Office'] -and $info.Office) { $info.Office.Version = [string]$info.Office.Version }
        $restore = New-OpRestorePoint -Configuration $configuration -Confirm:$false
        if ($restore -and $restore.PSObject.Properties['CreationTime'] -and $restore.CreationTime) { $restore.CreationTime = ([datetime]$restore.CreationTime).ToString('o') }
        $session = [pscustomobject]@{ StartTime = (Get-Date).ToString('o'); Before = $info; RestorePoint = $restore; Steps = @() }
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
    Write-OpLog "Étape $StepId : $($result.State), $($result.Reason)"

    $session.Steps = @(@($session.Steps | Where-Object { $_ -and $_.Id -ne $StepId }) + $result)
    # Chaque appel de la CLI a son journal : le rapport en reprend les avertissements et les erreurs.
    $logPaths = @()
    if ($session.PSObject.Properties['LogPaths']) { $logPaths = @($session.LogPaths | Where-Object { $_ }) }
    if ($log -and $log.Path -and $logPaths -notcontains $log.Path) { $logPaths += $log.Path }
    $session | Add-Member -NotePropertyName LogPaths -NotePropertyValue $logPaths -Force
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $sessionPath -Parent) -ErrorAction Stop | Out-Null
    $tmp = "$sessionPath.tmp"
    [System.IO.File]::WriteAllText($tmp, ($session | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $sessionPath -Force -ErrorAction Stop
    $result
}
