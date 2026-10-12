function Get-OpPowerStatus {
    <#
    .SYNOPSIS
        Relève l'alimentation du PC : batterie présente, sur secteur ou sur batterie, charge restante.

    .DESCRIPTION
        Lecture seule (cahier des charges 8.2 : portable sur batterie). Source : SystemInformation.PowerStatus
        (System.Windows.Forms). OnBattery est vrai seulement si le PC a une batterie et que le secteur est
        débranché (PowerLineStatus Offline) ; un état secteur inconnu ne le rend pas vrai, et une charge inconnue
        (Unknown, qui contient l'indicateur NoSystemBattery) compte comme une absence de batterie. BatteryPercent vaut $null
        sans batterie ou si la charge est inconnue.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $status = [System.Windows.Forms.SystemInformation]::PowerStatus
    $hasBattery = -not $status.BatteryChargeStatus.HasFlag([System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery)
    $percent = $null
    if ($hasBattery -and $status.BatteryLifePercent -ge 0 -and $status.BatteryLifePercent -le 1) { $percent = [int][math]::Round($status.BatteryLifePercent * 100) }
    [pscustomobject]@{
        HasBattery     = $hasBattery
        OnBattery      = $hasBattery -and $status.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline
        BatteryPercent = $percent
    }
}
