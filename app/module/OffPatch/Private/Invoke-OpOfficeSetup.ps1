function Invoke-OpOfficeSetup {
    <#
    .SYNOPSIS
        Lance setup.exe de l'ODT avec un XML de configuration, puis recueille ses journaux et supprime le XML, quoi
        qu'il arrive.

    .DESCRIPTION
        Mise à jour d'un Office Click-to-Run existant depuis la source locale de son canal (/configure), ou
        téléchargement d'une source côté dépôt (/download) (cahier des charges 7.1, 8.5). setup.exe est lancé par
        Invoke-OpProcess avec le délai maximal odtTimeoutMinutes (l'ODT peut attendre le réseau sans fin, R-10).
        Dans un bloc finally, donc sur tous les chemins de sortie (réussite, erreur, délai dépassé, exception) :
          - copie dans le dossier de session des journaux de l'ODT écrits pendant l'étape dans les dossiers de
            LogSearchDirectory (l'ODT les écrit dans le TEMP de l'utilisateur, sous la forme
            <NOMDUPC>-AAAAMMJJ-HHMM.log, et n'applique pas <Logging Path>, R-08) ;
          - suppression du XML de configuration temporaire.
        Un échec de ces opérations est journalisé sans masquer l'erreur d'origine de l'étape.
        Renvoie le résultat d'Invoke-OpProcess, complété de la liste des journaux copiés (OdtLogs).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [ValidateSet('configure', 'download')][string]$Mode = 'configure',
        [Parameter(Mandatory)][ValidateRange(1, 1440)][int]$TimeoutMinutes,
        [Parameter(Mandatory)][string[]]$LogSearchDirectory,
        [string]$SessionLogDirectory,
        [datetime]$StepStart = (Get-Date).AddMinutes(-1),
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $result = $null
    $copied = New-Object System.Collections.Generic.List[string]
    try {
        $result = Invoke-OpProcess -FilePath $SetupPath -ArgumentList "/$Mode", $ConfigPath -TimeoutSeconds ($TimeoutMinutes * 60) -WorkingDirectory (Split-Path -Path $SetupPath -Parent)
    } finally {
        $namePattern = '^' + [regex]::Escape($ComputerName) + '-\d{8}-\d{4}\.log$'
        foreach ($directory in $LogSearchDirectory) {
            if (-not $SessionLogDirectory -or -not $directory -or -not (Test-Path -Path $directory -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -Path $directory -File -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $namePattern -and $_.LastWriteTime -ge $StepStart })) {
                try {
                    if ($PSCmdlet.ShouldProcess($SessionLogDirectory, "Copie de $($file.Name)")) {
                        New-Item -ItemType Directory -Force -Path $SessionLogDirectory -ErrorAction Stop | Out-Null
                        Copy-Item -Path $file.FullName -Destination (Join-Path $SessionLogDirectory $file.Name) -Force -ErrorAction Stop
                        $copied.Add($file.Name)
                    }
                } catch {
                    Write-OpLog "Journal de l'ODT non copié dans la session : $($file.FullName) : $($_.Exception.Message)" -Level WARN
                }
            }
        }
        if (Test-Path -Path $ConfigPath -PathType Leaf) {
            try {
                if ($PSCmdlet.ShouldProcess($ConfigPath, 'Suppression du XML de configuration')) { Remove-Item -Path $ConfigPath -Force -ErrorAction Stop }
            } catch {
                Write-OpLog "XML de configuration de l'ODT non supprimé : $ConfigPath : $($_.Exception.Message)" -Level WARN
            }
        }
    }
    if ($result) { $result | Add-Member -NotePropertyName OdtLogs -NotePropertyValue $copied.ToArray() -PassThru }
}
