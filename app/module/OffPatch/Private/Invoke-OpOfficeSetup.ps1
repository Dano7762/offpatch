function Invoke-OpOfficeSetup {
    <#
    .SYNOPSIS
        Lance setup.exe de l'ODT avec un XML de configuration, puis masque et recueille ses journaux, quoi qu'il
        arrive.

    .DESCRIPTION
        Étape Office (cahier des charges 8.5). setup.exe est lancé par Invoke-OpProcess avec le délai maximal
        odtTimeoutMinutes (l'ODT peut attendre le réseau sans fin, R-10). Dans un bloc finally, donc sur tous les
        chemins de sortie (réussite, erreur, délai dépassé, exception) :
          - masquage de la clé de produit dans les journaux de l'ODT produits depuis le début de l'étape, puis
            copie dans le dossier de session (Protect-OpOdtLog) ;
          - suppression du XML de configuration, qui peut contenir la clé (8.5, 11).
        Renvoie le résultat d'Invoke-OpProcess, complété de la liste des journaux traités (OdtLogs).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [ValidateSet('configure', 'download')][string]$Mode = 'configure',
        [Parameter(Mandatory)][ValidateRange(1, 1440)][int]$TimeoutMinutes,
        [string]$ProductKey,
        [Parameter(Mandatory)][string[]]$LogSearchDirectory,
        [string]$SessionLogDirectory,
        [datetime]$StepStart = (Get-Date).AddMinutes(-1)
    )

    $result = $null
    $odtLogs = @()
    try {
        $result = Invoke-OpProcess -FilePath $SetupPath -ArgumentList "/$Mode", $ConfigPath -TimeoutSeconds ($TimeoutMinutes * 60) -WorkingDirectory (Split-Path -Path $SetupPath -Parent)
    } finally {
        $odtLogs = @(Protect-OpOdtLog -Since $StepStart -SearchDirectory $LogSearchDirectory -ProductKey $ProductKey -Destination $SessionLogDirectory)
        if (Test-Path -Path $ConfigPath -PathType Leaf) {
            try {
                if ($PSCmdlet.ShouldProcess($ConfigPath, 'Suppression du XML de configuration')) { Remove-Item -Path $ConfigPath -Force -ErrorAction Stop }
            } catch {
                Write-OpLog "XML de configuration de l'ODT non supprimé : $ConfigPath : $($_.Exception.Message)" -Level ERROR
            }
        }
    }
    if ($result) { $result | Add-Member -NotePropertyName OdtLogs -NotePropertyValue $odtLogs -PassThru }
}
