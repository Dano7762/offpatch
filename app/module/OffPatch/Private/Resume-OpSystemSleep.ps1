function Resume-OpSystemSleep {
    <#
    .SYNOPSIS
        Rend la mise en veille automatique au PC, dans l'état d'avant Suspend-OpSystemSleep.

    .DESCRIPTION
        Cahier des charges 8.6. PreviousState : valeur renvoyée par Suspend-OpSystemSleep ($null : rien à faire).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()][object]$PreviousState
    )

    if ($null -eq $PreviousState -or -not ('OffPatch.Power' -as [type])) { return }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Mise en veille automatique rétablie')) { return }
    # ES_CONTINUOUS avec les indicateurs d'avant : sans indicateur, la demande de ce thread est levée.
    [void][OffPatch.Power]::SetThreadExecutionState([uint32]([uint32]2147483648 -bor [uint32]$PreviousState))
}
