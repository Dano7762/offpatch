function Get-OpVolumeInfo {
    <#
    .SYNOPSIS
        Lit le volume d'un chemin : racine, système de fichiers, espace libre et total, type de lecteur.

    .DESCRIPTION
        System.IO.DriveInfo, disponible partout sous PowerShell 5.1 (ni WMI ni module de stockage). Lecteur absent
        ou pas prêt : IsReady faux, les autres valeurs vides.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $drive = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path)))
    if (-not $drive.IsReady) { return [pscustomobject]@{ Root = $drive.Name; IsReady = $false; FileSystem = $null; FreeBytes = $null; TotalBytes = $null; DriveType = [string]$drive.DriveType; Label = $null } }
    [pscustomobject]@{
        Root = $drive.Name; IsReady = $true; FileSystem = $drive.DriveFormat; FreeBytes = $drive.AvailableFreeSpace
        TotalBytes = $drive.TotalSize; DriveType = [string]$drive.DriveType; Label = $drive.VolumeLabel
    }
}
