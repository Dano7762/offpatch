function Get-OpSessionStatus {
    <#
    .SYNOPSIS
        Décrit, en lecture seule, la session d'installation en cours (state.json), ou rien s'il n'y en a pas.

    .DESCRIPTION
        Cahier des charges 8.6 : sert au bouton « Reprendre la session interrompue » et à la reprise par -Resume.
        Renvoie SessionId, Mode (Manual ou Auto), StartTime, RebootCount, StepCount et Error ; un état illisible ou
        d'un autre schéma n'est pas une exception : Mode vide et motif dans Error.

    .PARAMETER Path
        Chemin de state.json ; par défaut celui de ProgramData\OffPatch.

    .EXAMPLE
        if ((Get-OpSessionStatus).Mode -eq 'Auto') { 'Session automatique à reprendre' }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    try {
        $state = Read-OpSessionState -Path $Path
    } catch {
        return [pscustomobject]@{ SessionId = $null; Mode = $null; StartTime = $null; RebootCount = 0; StepCount = 0; Error = $_.Exception.Message }
    }
    if (-not $state) { return }
    $mode = $null
    if ($state.PSObject.Properties['mode']) { $mode = [string]$state.mode }
    $start = $null
    if ($state.PSObject.Properties['startTime']) { $start = [string]$state.startTime }
    $reboots = 0
    if ($state.PSObject.Properties['rebootCount']) { $reboots = [int]$state.rebootCount }
    $steps = 0
    if ($state.PSObject.Properties['steps']) { $steps = @($state.steps | Where-Object { $_ }).Count }
    [pscustomobject]@{ SessionId = [string]$state.sessionId; Mode = $mode; StartTime = $start; RebootCount = $reboots; StepCount = $steps; Error = $null }
}
