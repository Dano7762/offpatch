function Get-OpFreeSpace {
    <#
    .SYNOPSIS
        Renvoie l'espace libre, en octets, du volume qui porte un chemin ; $null s'il ne peut pas être lu.

    .DESCRIPTION
        Lecture seule. Le chemin peut ne pas exister encore (dépôt neuf) : seule sa racine de volume compte. Un
        chemin réseau (UNC) ou un volume illisible renvoie $null, sans erreur : l'appelant le signale.
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[long]])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    try {
        $volume = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
        if (-not $volume -or $volume.StartsWith('\\')) { return $null }
        [long](New-Object System.IO.DriveInfo($volume)).AvailableFreeSpace
    } catch {
        $null
    }
}
