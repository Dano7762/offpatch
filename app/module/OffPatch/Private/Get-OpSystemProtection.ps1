function Get-OpSystemProtection {
    <#
    .SYNOPSIS
        Indique si la protection du système (points de restauration) est active sur le volume système.

    .DESCRIPTION
        Lecture seule (cahier des charges 8.2). Deux indicateurs, qui doivent concorder (mesurés sur runner, run
        37476821152) :
          - Spp : une valeur de HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients cite le volume système
            (mesuré, non documenté) ;
          - Storage : Win32_ShadowStorage réserve des clichés pour le volume système (classe WMI documentée).
        Active seulement si les deux sont vrais ; désaccord ou absence : inactive. Renvoie Active, Spp, Storage.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$($env:SystemDrive)'" -ErrorAction Stop | Select-Object -First 1
    $spp = $false
    $clients = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -ErrorAction SilentlyContinue
    if ($clients -and $volume) {
        $spp = @($clients.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and (@($_.Value) -join ';') -like "*$($volume.DeviceID)*" }).Count -gt 0
    }
    $storage = $false
    if ($volume) {
        $storage = @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction SilentlyContinue | Where-Object { $_.Volume.DeviceID -eq $volume.DeviceID }).Count -gt 0
    }
    [pscustomobject]@{ Active = ($spp -and $storage); Spp = $spp; Storage = $storage }
}
