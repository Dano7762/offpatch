function Get-OpInitialSessionState {
    <#
    .SYNOPSIS
        Construit l'état d'une nouvelle session d'installation (contenu de state.json), sans l'écrire.

    .DESCRIPTION
        Cahier des charges 8.6. Champs : schemaVersion, sessionId, mode (Manual ou Auto), startTime, rebootCount,
        support (volumeSerial, relativeRoot : retrouver le support après un redémarrage, même sous une autre lettre),
        before (relevé du PC au début), restorePoint, steps (résultat de chaque étape exécutée) et logPaths (journal
        de chaque appel). Versions et dates en texte : ConvertTo-Json de PowerShell 5.1 en ferait des objets.
        Écrire par Save-OpSessionState.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][pscustomobject]$SystemInfo,
        [pscustomobject]$RestorePoint,
        [ValidateSet('Manual', 'Auto')][string]$Mode = 'Manual'
    )

    if ($SystemInfo.PSObject.Properties['Office'] -and $SystemInfo.Office -and $SystemInfo.Office.PSObject.Properties['Version']) {
        $SystemInfo.Office.Version = [string]$SystemInfo.Office.Version
    }
    if ($RestorePoint -and $RestorePoint.PSObject.Properties['CreationTime'] -and $RestorePoint.CreationTime) {
        $RestorePoint.CreationTime = ([datetime]$RestorePoint.CreationTime).ToString('o')
    }
    $support = Get-OpSupportIdentity -Root $Root
    [pscustomobject][ordered]@{
        schemaVersion = 1
        sessionId     = [guid]::NewGuid().ToString()
        mode          = $Mode
        startTime     = (Get-Date).ToString('o')
        rebootCount   = 0
        support       = [pscustomobject]@{ volumeSerial = $support.VolumeSerial; relativeRoot = $support.RelativeRoot }
        before        = $SystemInfo
        restorePoint  = $RestorePoint
        steps         = @()
        logPaths      = @()
    }
}
