function Install-OpDefenderUpdate {
    <#
    .SYNOPSIS
        Exécute une étape Defender (plateforme ou définitions) et juge son résultat sur la version relevée.

    .DESCRIPTION
        Cahier des charges 8.4 (R-06). Avant l'étape, SHA-256 du fichier revérifié (écart : Error, rien n'est lancé),
        puis attente que Defender soit en service (AMRunningMode Normal, Passive Mode ou EDR Block Mode), bornée à
        WaitSeconds ; au-delà, avertissement et lancement quand même, le jugement par la version tranchera.
          - defender-platform : updateplatform.<arch>fre_….exe lancé sans argument, puis attente du retour de Defender
            dans le mode relevé avant l'étape (Normal sur un poste ordinaire), bornée à WaitSeconds, avec
            avertissement en cas de dépassement. Réussite si AMProductVersion ≥ version du manifeste.
          - defender : mpam-fe.exe -q. Réussite si AntivirusSignatureVersion ≥ version du manifeste ; sinon une
            seconde tentative après RetryDelaySeconds, puis Error avec le code retour. Le code retour seul ne prouve
            rien : mpam-fe.exe peut renvoyer 0 sans rien appliquer.
        Renvoie Id, Category, State (UpToDate si la version est atteinte, Error sinon), Reason, Before, Installed,
        Available et ExitCode (dernier lancement).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][string]$Depot,
        [ValidateRange(1, 3600)][int]$WaitSeconds = 120,
        [ValidateRange(0, 3600)][int]$RetryDelaySeconds = 30,
        [ValidateRange(1, 60)][int]$PollSeconds = 5
    )

    # ponytail: délai maximal fixe ; mesuré 16 à 35 s, et 185 s pour l'échec 0x800705B4 (R-06).
    $processTimeoutSeconds = 900
    $running = 'Normal', 'Passive Mode', 'EDR Block Mode'
    $polls = [math]::Ceiling($WaitSeconds / $PollSeconds)
    $pollDelay = $PollSeconds
    $isPlatform = $Item.category -eq 'defender-platform'
    if (-not $isPlatform -and $Item.category -ne 'defender') { throw "Install-OpDefenderUpdate : catégorie $($Item.category) non prise en charge." }
    $versionProperty = 'AntivirusSignatureVersion'
    if ($isPlatform) { $versionProperty = 'AMProductVersion' }
    $available = [string]$Item.version
    $file = @($Item.files)[0]

    function Get-Status {
        try { Get-MpComputerStatus -ErrorAction Stop } catch { $null }
    }
    function Get-Mode($Status) {
        if ($Status -and $Status.PSObject.Properties['AMRunningMode']) { return [string]$Status.AMRunningMode }
        ''
    }
    function Get-InstalledVersion($Status) {
        $v = $null
        if ($Status -and $Status.PSObject.Properties[$versionProperty] -and [version]::TryParse(([string]$Status.$versionProperty).Trim(), [ref]$v)) { return $v }
        $null
    }
    # Attente bornée (nombre de relevés, pas l'horloge) ; renvoie le dernier relevé, $null si Defender ne répond pas.
    function Wait-Mode([string[]]$Accepted) {
        $status = Get-Status
        for ($i = 0; $i -lt $polls -and $Accepted -notcontains (Get-Mode $status); $i++) {
            Start-Sleep -Seconds $pollDelay
            $status = Get-Status
        }
        [pscustomobject]@{ Status = $status; Ready = ($Accepted -contains (Get-Mode $status)) }
    }
    function ConvertTo-StepResult([string]$State, [string]$Reason, $Before, $Installed, $ExitCode) {
        [pscustomobject]@{
            Id = $Item.id; Category = $Item.category; State = $State; Reason = $Reason
            Before = $(if ($Before) { "$Before" }); Installed = $(if ($Installed) { "$Installed" }); Available = $available; ExitCode = $ExitCode
        }
    }

    $problems = @(Test-OpItemFileHash -Depot $Depot -File @($Item.files))
    if ($problems.Count -gt 0) {
        $reason = "Fichier non conforme au manifeste, étape non lancée : $($problems -join ' ')"
        Write-OpLog "$($Item.id) : $reason" -Level ERROR
        return (ConvertTo-StepResult 'Error' $reason $null $null $null)
    }
    $path = Join-Path $Depot ([string]$file.path -replace '/', '\')
    $arguments = @('-q')
    if ($isPlatform) { $arguments = @() }
    if (-not $PSCmdlet.ShouldProcess($path, "Mise à jour Defender $available")) { return }

    $ready = Wait-Mode $running
    if (-not $ready.Ready) { Write-OpLog "$($Item.id) : Defender n'est pas en service après $WaitSeconds s (AMRunningMode : $(Get-Mode $ready.Status)) ; lancement quand même." -Level WARN }
    $modeBefore = Get-Mode $ready.Status
    $before = Get-InstalledVersion $ready.Status
    $wanted = [version]$available

    $attempts = 1
    if (-not $isPlatform) { $attempts = 2 }
    $exitCode = $null
    $installed = $before
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-OpLog "$($Item.id) : $versionProperty $installed après le lancement, $available attendue ; nouvelle tentative dans $RetryDelaySeconds s." -Level WARN
            Start-Sleep -Seconds $RetryDelaySeconds
            [void](Wait-Mode $running)
        }
        Write-OpLog "$($Item.id) : lancement de $(Split-Path -Leaf $path) $($arguments -join ' ') (tentative $attempt)."
        $run = Invoke-OpProcess -FilePath $path -ArgumentList $arguments -TimeoutSeconds $processTimeoutSeconds
        $exitCode = $run.ExitCode
        Write-OpLog "$($Item.id) : code retour $(if ($run.TimedOut) { "aucun (délai de $processTimeoutSeconds s dépassé)" } else { $exitCode }) en $($run.Seconds) s."
        $accepted = $running
        if ($isPlatform -and $modeBefore) { $accepted = @($modeBefore) }
        $after = Wait-Mode $accepted
        if (-not $after.Ready) { Write-OpLog "$($Item.id) : Defender n'est pas revenu en mode $($accepted -join ' ou ') après $WaitSeconds s (AMRunningMode : $(Get-Mode $after.Status))." -Level WARN }
        $installed = Get-InstalledVersion $after.Status
        if ($installed -and $installed -ge $wanted) {
            Write-OpLog "$($Item.id) : $versionProperty $before -> $installed."
            return (ConvertTo-StepResult 'UpToDate' "$versionProperty $installed ≥ $available." $before $installed $exitCode)
        }
    }
    $reason = "$versionProperty $installed après le lancement, $available attendue (code retour $(if ($null -eq $exitCode) { 'absent, délai dépassé' } else { $exitCode }))."
    Write-OpLog "$($Item.id) : $reason" -Level ERROR
    ConvertTo-StepResult 'Error' $reason $before $installed $exitCode
}
