function ConvertTo-OpStateLabel {
    <#
    .SYNOPSIS
        Libellé français d'un état d'étape (rapport, interface).

    .DESCRIPTION
        États de Get-OpUpdateState et Get-OpInstallPlan (cahier des charges 8.3). Un état inconnu est renvoyé tel quel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$State
    )

    $labels = @{ UpToDate = 'À jour'; Pending = 'À installer'; NotApplicable = 'Non applicable'; MissingFromDepot = 'Absent du dépôt'; SkippedPrerequisite = 'Ignorée (prérequis)'; Error = 'Erreur' }
    if ($State -and $labels.ContainsKey($State)) { return $labels[$State] }
    $State
}
