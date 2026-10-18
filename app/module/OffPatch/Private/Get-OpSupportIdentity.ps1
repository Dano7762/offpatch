function Get-OpSupportIdentity {
    <#
    .SYNOPSIS
        Identifie le support de l'outil : numéro de série du volume et chemin de la racine sans lettre de lecteur.

    .DESCRIPTION
        Lecture seule (cahier des charges 8.6). La lettre du support peut changer d'un démarrage à l'autre : la reprise
        retrouve le support par son numéro de série de volume (Win32_LogicalDisk.VolumeSerialNumber) et le fichier
        offpatch.root au chemin relatif gardé ici. Numéro de série illisible (volume réseau, WMI en échec) : $null.
        Renvoie Drive (par exemple E:), VolumeSerial et RelativeRoot (« . » à la racine du volume).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $drive = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    $relative = $full.Substring($drive.Length).TrimStart('\')
    if (-not $relative) { $relative = '.' }
    $serial = $null
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop | Select-Object -First 1
        if ($disk -and $disk.VolumeSerialNumber) { $serial = [string]$disk.VolumeSerialNumber }
    } catch {
        Write-OpLog "Numéro de série du volume $drive illisible : $($_.Exception.Message)" -Level WARN
    }
    [pscustomobject]@{ Drive = $drive; VolumeSerial = $serial; RelativeRoot = $relative }
}
