function Get-OpPendingReboot {
    <#
    .SYNOPSIS
        Liste les indicateurs d'un redémarrage en attente : maintenance (CBS), Windows Update, renommages de fichiers.

    .DESCRIPTION
        Lecture seule (cahier des charges 8.2). Indicateurs, sources dans RECHERCHE.md (contrôles préalables) :
          - CBS : clé HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending, présente
            après chaque code 3010 de DISM (R-14) ;
          - WindowsUpdate : clé ...\WindowsUpdate\Auto Update\RebootRequired ;
          - FileRename : valeur PendingFileRenameOperations non vide sous Session Manager (MoveFileEx).
        Renvoie les noms des indicateurs présents (CBS, WindowsUpdate, FileRename), tableau vide sinon.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $found = New-Object System.Collections.Generic.List[string]
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
    if (Test-Path -LiteralPath "$cv\Component Based Servicing\RebootPending") { $found.Add('CBS') }
    if (Test-Path -LiteralPath "$cv\WindowsUpdate\Auto Update\RebootRequired") { $found.Add('WindowsUpdate') }
    $session = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    if ($session -and $null -ne $session.PSObject.Properties['PendingFileRenameOperations'] -and @($session.PendingFileRenameOperations | Where-Object { $_ }).Count -gt 0) { $found.Add('FileRename') }
    $found.ToArray()
}
