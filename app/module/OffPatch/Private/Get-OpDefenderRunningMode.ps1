function Get-OpDefenderRunningMode {
    <#
    .SYNOPSIS
        Mode de fonctionnement de Defender tiré d'un relevé Get-MpComputerStatus.

    .DESCRIPTION
        Lecture seule (R-06). AMRunningMode quand le relevé le porte (Normal, Passive Mode, EDR Block Mode,
        Not running…). Une plateforme ancienne ne l'a pas (relevé sur Windows 10 22H2, plateforme 4.18.1909.6,
        2026-10-18) : Defender est alors jugé Normal si AMServiceEnabled et AntivirusEnabled sont vrais, sinon le
        mode est vide (Defender non en service). Relevé absent : chaîne vide.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        $Status
    )

    if (-not $Status) { return '' }
    $p = $Status.PSObject.Properties
    if ($p['AMRunningMode'] -and [string]$Status.AMRunningMode) { return [string]$Status.AMRunningMode }
    if ($p['AMServiceEnabled'] -and $p['AntivirusEnabled'] -and $Status.AMServiceEnabled -and $Status.AntivirusEnabled) { return 'Normal' }
    ''
}
