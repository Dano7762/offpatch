function Test-OpElevated {
    <#
    .SYNOPSIS
        Indique si la session PowerShell courante a les droits d'administrateur (jeton élevé).

    .DESCRIPTION
        Lecture seule. Sert avant les opérations qui exigent l'élévation, par exemple l'extraction de l'ODT, dont
        l'exécutable demande requireAdministrator (mesuré le 2026-10-12, R-07).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
