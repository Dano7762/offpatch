function Invoke-OpAutoSession {
    <#
    .SYNOPSIS
        Déroule la session automatique : étapes du plan dans l'ordre, redémarrages avec reprise, rapport de fin.

    .DESCRIPTION
        Cahier des charges 8.6. Une seule validation au départ (confirmation, sauf -Confirm:$false à la reprise).
        Tant que le plan recalculé propose une étape Pending, elle est exécutée par Invoke-OpInstallStep (session
        en mode Auto). Une étape en erreur est retentée une fois, puis abandonnée (Invoke-OpInstallStep) ; la session
        continue avec les suivantes. Une étape réussie dans la session n'est pas relancée, même si le plan la
        propose encore (SSU jugée sur l'UBR après une cumulative annulée).
        Après une étape suivie d'un redémarrage (RebootAfter), Restart-OpSession crée la tâche de reprise, décompte et
        redémarre : la fonction renvoie Restarting, et resume.ps1 relancera la session à l'ouverture de session.
        Redémarrage annulé : Cancelled, l'état est conservé. Limite maxAutoReboots atteinte : la session s'arrête et
        se termine par le rapport.
        Plus d'étape à faire : rapport et fin de session (Write-OpInstallReport), Completed.
        Windows 10 sans ESU actif (contrôle préalable SkipWindowsInAuto) : les étapes Windows (catégories windows-*)
        et les étapes .NET (dotnet, R-19) sont ignorées et signalées au journal, sauf -ForceWindows.
        Une étape installée avant un redémarrage (UpToDate, redémarrage nécessaire) que le plan propose de nouveau
        après la reprise a été annulée par Windows au redémarrage : elle passe en Error « non appliquée après
        redémarrage (retour arrière probable) » dans state.json, sans nouvelle tentative (8.4).
        Une session manuelle en cours (CLI) est refusée : la terminer d'abord par son rapport.
        Pas de mise en veille automatique du PC pendant tout l'appel (Suspend-OpSystemSleep), rétablie à la fin.
        Renvoie Result (Restarting, Cancelled ou Completed), ReportPath et Steps (résultats de cet appel).

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER CountdownSeconds
        Durée du compte à rebours avant redémarrage ; par défaut client.rebootCountdownSeconds de settings.json.

    .PARAMETER ForceWindows
        Windows 10 sans ESU actif ou détectable : exécute quand même les étapes Windows et .NET (forçage du
        récapitulatif, R-04). Sans ce paramètre, elles sont ignorées et signalées au journal.

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
        [switch]$ForceWindows,
        [scriptblock]$OnStep,
        [scriptblock]$OnTick,
        [scriptblock]$IsCancelled
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $session = Read-OpSessionState
    if ($session -and $session.mode -ne 'Auto') { throw 'Session manuelle en cours : la terminer par son rapport (CLI, -Action Report) avant le mode automatique.' }
    $info = Get-OpSystemInfo -Root $Root
    $checks = @(Test-OpPreflight -Root $Root -SystemInfo $info)
    $blocking = @($checks | Where-Object { $_.Result -eq 'Blocking' })
    if ($blocking.Count -gt 0) { throw "Session automatique refusée, contrôle préalable bloquant : $(($blocking | ForEach-Object { "$($_.Label) : $($_.Message)" }) -join ' ; ')" }
    # Windows 10 sans ESU actif (R-04) : étapes Windows ignorées en mode auto, sauf forçage au récapitulatif. Le
    # forçage est gardé dans state.json (forceWindows) : la reprise après redémarrage se fait sans paramètre.
    if ($session -and $session.PSObject.Properties['forceWindows'] -and $session.forceWindows) { $ForceWindows = [switch]$true }
    $skipWindows = -not $ForceWindows -and @($checks | Where-Object { $_.Action -eq 'SkipWindowsInAuto' }).Count -gt 0
    $verb = 'Démarrage'
    if ($session) { $verb = 'Reprise' }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "$verb de la session automatique")) { return }
    Write-OpLog "$verb de la session automatique."
    # Pas de mise en veille de toute la session, compte à rebours et rapport compris.
    $sleep = Suspend-OpSystemSleep -Confirm:$false
    try {
        $results = @()
        $succeeded = @{}
        $attempts = @{}
        $restart = $null
        while ($true) {
            # Étapes qui ne seront plus tentées : elles ne remplissent plus aucun prérequis (enablement package après une
            # cumulative abandonnée).
            $excluded = @($attempts.Keys | Where-Object { [int]$attempts[$_] -ge 2 })
            $plan = @(Get-OpInstallPlan -Root $Root -SystemInfo (Get-OpSystemInfo -Root $Root) -ExcludeId $excluded)
            $pending = @($plan | Where-Object { $_.State -eq 'Pending' -and -not $succeeded.ContainsKey($_.Id) -and [int]$attempts[$_.Id] -lt 2 })
            if ($skipWindows) {
                # .NET aussi : sans ESU, sa cumulative s'installe puis est écartée au redémarrage sans erreur (R-19).
                $esuOnly = { $_.Category -like 'windows-*' -or $_.Category -eq 'dotnet' }
                foreach ($s in @($pending | Where-Object $esuOnly)) {
                    Write-OpLog "Étape $($s.Id) ignorée : ESU absent ou indétectable, étape Windows ou .NET non forcée en mode auto." -Level WARN
                    $attempts[$s.Id] = 2
                }
                $pending = @($pending | Where-Object { -not (& $esuOnly) })
            }
            # Installée avant un redémarrage (UpToDate, redémarrage nécessaire) mais de nouveau à installer : Windows l'a
            # annulée au redémarrage (8.4, second temps du jugement). Erreur, sans nouvelle tentative.
            $state = Read-OpSessionState
            $rolledBack = @()
            if ($state) {
                foreach ($s in $pending) {
                    $previous = @($state.steps | Where-Object { $_ -and $_.Id -eq $s.Id }) | Select-Object -First 1
                    if ($previous -and $previous.State -eq 'UpToDate' -and $previous.PSObject.Properties['RebootRequired'] -and $previous.RebootRequired) {
                        $previous.State = 'Error'
                        $previous.Reason = "$($previous.Reason) Non appliquée après redémarrage (retour arrière probable)."
                        Write-OpLog "Étape $($s.Id) : installée mais non appliquée après redémarrage (retour arrière probable) ; pas de nouvelle tentative." -Level ERROR
                        $attempts[$s.Id] = 2
                        $rolledBack += $s.Id
                    }
                    # Réussie plus tôt dans la session sans redémarrage, mais encore proposée (SSU jugée sur l'UBR, que la
                    # cumulative annulée n'a pas fait monter) : pas de nouvelle installation.
                    elseif ($previous -and $previous.State -eq 'UpToDate') { $succeeded[$s.Id] = $true }
                }
            }
            if ($rolledBack.Count -gt 0) {
                Save-OpSessionState -State $state -Confirm:$false
                continue
            }
            $pending = @($pending | Where-Object { $rolledBack -notcontains $_.Id -and -not $succeeded.ContainsKey($_.Id) })
            $next = $pending | Select-Object -First 1
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
            if ($ForceWindows) {
                $state = Read-OpSessionState
                if (-not $state.PSObject.Properties['forceWindows']) {
                    $state | Add-Member -NotePropertyName forceWindows -NotePropertyValue $true
                    Save-OpSessionState -State $state -Confirm:$false
                }
            }
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
    } finally {
        Resume-OpSystemSleep -PreviousState $sleep -Confirm:$false
    }
}
