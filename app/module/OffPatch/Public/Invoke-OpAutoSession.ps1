function Invoke-OpAutoSession {
    <#
    .SYNOPSIS
        Déroule la session automatique : étapes du plan dans l'ordre, redémarrages avec reprise, rapport de fin.

    .DESCRIPTION
        Cahier des charges 8.6. Une seule validation au départ (confirmation, sauf -Confirm:$false à la reprise).
        Tant que le plan recalculé propose une étape Pending, elle est exécutée par Invoke-OpInstallStep (session
        en mode Auto). Une étape en erreur est retentée une fois, puis abandonnée (Invoke-OpInstallStep) ; la session
        continue avec les suivantes. Dans un même appel, une étape réussie n'est pas relancée, même si le plan la
        propose encore.
        Après une étape suivie d'un redémarrage (RebootAfter), Restart-OpSession crée la tâche de reprise, décompte et
        redémarre : la fonction renvoie Restarting, et resume.ps1 relancera la session à l'ouverture de session.
        Redémarrage annulé : Cancelled, l'état est conservé. Limite maxAutoReboots atteinte : la session s'arrête et
        se termine par le rapport.
        Plus d'étape à faire : rapport et fin de session (Write-OpInstallReport), Completed.
        Une session manuelle en cours (CLI) est refusée : la terminer d'abord par son rapport.
        Renvoie Result (Restarting, Cancelled ou Completed), ReportPath et Steps (résultats de cet appel).

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER CountdownSeconds
        Durée du compte à rebours avant redémarrage ; par défaut client.rebootCountdownSeconds de settings.json.

    .PARAMETER OnStep
        Bloc appelé avant chaque étape avec la ligne du plan, puis après avec son résultat (affichage).

    .PARAMETER OnTick
        Bloc appelé à chaque seconde du compte à rebours avec les secondes restantes.

    .PARAMETER IsCancelled
        Bloc consulté à chaque seconde du compte à rebours ; vrai : redémarrage annulé.

    .EXAMPLE
        Invoke-OpAutoSession -OnStep { param($s) Write-Host "$($s.Id) : $($s.State)" }

    .EXAMPLE
        Invoke-OpAutoSession -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [ValidateRange(-1, 3600)][int]$CountdownSeconds = -1,
        [scriptblock]$OnStep,
        [scriptblock]$OnTick,
        [scriptblock]$IsCancelled
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $session = Read-OpSessionState
    if ($session -and $session.mode -ne 'Auto') { throw 'Session manuelle en cours : la terminer par son rapport (CLI, -Action Report) avant le mode automatique.' }
    $info = Get-OpSystemInfo -Root $Root
    $blocking = @(Test-OpPreflight -Root $Root -SystemInfo $info | Where-Object { $_.Result -eq 'Blocking' })
    if ($blocking.Count -gt 0) { throw "Session automatique refusée, contrôle préalable bloquant : $(($blocking | ForEach-Object { "$($_.Label) : $($_.Message)" }) -join ' ; ')" }
    $verb = 'Démarrage'
    if ($session) { $verb = 'Reprise' }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "$verb de la session automatique")) { return }
    Write-OpLog "$verb de la session automatique."

    $results = @()
    $succeeded = @{}
    $attempts = @{}
    $restart = $null
    while ($true) {
        $plan = @(Get-OpInstallPlan -Root $Root -SystemInfo (Get-OpSystemInfo -Root $Root))
        $next = @($plan | Where-Object { $_.State -eq 'Pending' -and -not $succeeded.ContainsKey($_.Id) -and [int]$attempts[$_.Id] -lt 2 }) | Select-Object -First 1
        if (-not $next) { break }
        $attempts[$next.Id] = [int]$attempts[$next.Id] + 1
        if ($OnStep) { & $OnStep $next }
        try {
            $result = Invoke-OpInstallStep -StepId $next.Id -Root $Root -Mode Auto -Confirm:$false
        } catch {
            # Étape refusée (déjà abandonnée, contrôle devenu bloquant…) : signalée, la session continue.
            Write-OpLog "Étape $($next.Id) non exécutée : $($_.Exception.Message)" -Level WARN
            $attempts[$next.Id] = 2
            continue
        }
        $results += $result
        if ($OnStep) { & $OnStep $result }
        if ($result.State -eq 'Error') { continue }
        $succeeded[$next.Id] = $true
        if (-not $result.RebootAfter) { continue }
        $countdown = @{}
        if ($CountdownSeconds -ge 0) { $countdown.CountdownSeconds = $CountdownSeconds }
        $restart = Restart-OpSession -Root $Root -OnTick $OnTick -IsCancelled $IsCancelled -Confirm:$false @countdown
        if ($restart.Result -ne 'Refused') {
            return [pscustomobject]@{ Result = $restart.Result; ReportPath = $null; Steps = $results }
        }
        break
    }
    $path = Write-OpInstallReport -Root $Root -Confirm:$false
    Write-OpLog "Session automatique terminée : $($results.Count) étape(s) exécutée(s) dans ce passage."
    [pscustomobject]@{ Result = 'Completed'; ReportPath = $path; Steps = $results }
}
