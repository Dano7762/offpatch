function Restart-OpSession {
    <#
    .SYNOPSIS
        Redémarre le PC en cours de session automatique, après un compte à rebours, avec reprise à l'ouverture de
        session.

    .DESCRIPTION
        Cahier des charges 8.6. Sur la session de state.json :
          1. Garde-fou : au plus client.maxAutoReboots redémarrages par session ; au-delà, rien n'est fait
             (Refused), avec un avertissement : la session s'arrête là et le rapport le dira.
          2. Tâche de reprise OffPatch-Reprise et copie de resume.ps1 (Register-OpResumeTask).
          3. Compte à rebours de client.rebootCountdownSeconds (ou CountdownSeconds) : OnTick reçoit les secondes
             restantes à chaque seconde (affichage), IsCancelled est consulté à chaque seconde (bouton Annuler de
             l'interface). Annulé : la tâche est retirée, l'état est conservé (Cancelled).
          4. rebootCount incrémenté et state.json écrit avant le redémarrage, puis Restart-Computer -Force
             (Restarting).
        En mode manuel, aucune tâche n'est créée (8.7) : cette fonction ne sert qu'au mode automatique.
        Renvoie Result (Restarting, Cancelled ou Refused), RebootCount et MaxAutoReboots.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER CountdownSeconds
        Durée du compte à rebours ; par défaut client.rebootCountdownSeconds de settings.json.

    .PARAMETER OnTick
        Bloc appelé à chaque seconde avec le nombre de secondes restantes.

    .PARAMETER IsCancelled
        Bloc consulté à chaque seconde ; vrai : redémarrage annulé.

    .EXAMPLE
        Restart-OpSession -OnTick { param($s) Write-Host "Redémarrage dans $s s" }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [ValidateRange(0, 3600)][int]$CountdownSeconds = -1,
        [scriptblock]$OnTick,
        [scriptblock]$IsCancelled
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $client = (Get-OpConfiguration -Root $Root).Settings.client
    $max = [int]$client.maxAutoReboots
    if ($CountdownSeconds -lt 0) { $CountdownSeconds = [int]$client.rebootCountdownSeconds }
    $state = Read-OpSessionState
    if (-not $state) { throw 'Aucune session en cours (state.json absent) : redémarrage de session impossible.' }
    function ConvertTo-RestartResult([string]$Result) { [pscustomobject]@{ Result = $Result; RebootCount = [int]$state.rebootCount; MaxAutoReboots = $max } }

    if ([int]$state.rebootCount -ge $max) {
        Write-OpLog "Session $($state.sessionId) : $($state.rebootCount) redémarrage(s) déjà faits, limite maxAutoReboots ($max) atteinte : pas de nouveau redémarrage." -Level WARN
        return (ConvertTo-RestartResult 'Refused')
    }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Redémarrage $([int]$state.rebootCount + 1)/$max de la session après $CountdownSeconds s")) { return }

    [void](Register-OpResumeTask -Root $Root -Confirm:$false)
    for ($left = $CountdownSeconds; $left -gt 0; $left--) {
        if ($OnTick) { & $OnTick $left }
        if ($IsCancelled -and (& $IsCancelled)) {
            [void](Unregister-OpResumeTask -Confirm:$false)
            Write-OpLog "Session $($state.sessionId) : redémarrage annulé à $left s ; l'état est conservé."
            return (ConvertTo-RestartResult 'Cancelled')
        }
        Start-Sleep -Seconds 1
    }
    $state.rebootCount = [int]$state.rebootCount + 1
    Save-OpSessionState -State $state -Confirm:$false
    Write-OpLog "Session $($state.sessionId) : redémarrage $($state.rebootCount)/$max."
    Restart-Computer -Force -ErrorAction Stop
    ConvertTo-RestartResult 'Restarting'
}
