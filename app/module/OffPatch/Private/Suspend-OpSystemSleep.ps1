function Suspend-OpSystemSleep {
    <#
    .SYNOPSIS
        Empêche la mise en veille automatique du PC pendant un traitement long (installation, session).

    .DESCRIPTION
        Cahier des charges 8.6. SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) : demande d'activité
        portée par le thread en cours, sans aucun réglage d'alimentation modifié ; Windows la retire de lui-même à la
        fin du processus. L'écran peut s'éteindre ; la fermeture du capot d'un portable reste prioritaire.
        Renvoie l'état précédent, à rendre à Resume-OpSystemSleep (appels imbriqués : l'appel intérieur ne lève pas
        la demande de l'appel extérieur). Échec : journalisé, $null renvoyé, le traitement continue.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([uint32])]
    param()

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Mise en veille automatique suspendue')) { return }
    try {
        if (-not ('OffPatch.Power' -as [type])) {
            Add-Type -Namespace OffPatch -Name Power -ErrorAction Stop -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
        }
        # ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x1). Le littéral 0x80000000 serait un entier négatif.
        $previous = [OffPatch.Power]::SetThreadExecutionState([uint32]2147483649)
        if ($previous -eq 0) { throw 'SetThreadExecutionState a renvoyé 0.' }
        $previous
    } catch {
        Write-OpLog "Mise en veille non suspendue : $($_.Exception.Message)" -Level WARN
        $null
    }
}
