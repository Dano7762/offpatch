function Format-OpSize {
    <#
    .SYNOPSIS
        Écrit une taille en octets en Go (au-delà de 1 Gio) ou en Mo, à la française.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]$Bytes
    )

    if ($null -eq $Bytes) { return 'taille inconnue' }
    $fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    if ($Bytes -ge 1GB) { return ([double]$Bytes / 1GB).ToString('N2', $fr) + ' Go' }
    ([double]$Bytes / 1MB).ToString('N1', $fr) + ' Mo'
}
