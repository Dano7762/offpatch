function Protect-OpOdtLog {
    <#
    .SYNOPSIS
        Masque les journaux de l'ODT produits pendant une étape, puis les copie dans le dossier de session.

    .DESCRIPTION
        L'ODT écrit la clé de produit en clair dans son journal principal (UTF-16), dans le TEMP de l'utilisateur,
        sous la forme <NOMDUPC>-AAAAMMJJ-HHMM.log (R-08, cahier des charges 8.5). Pour chaque dossier de
        SearchDirectory, chaque fichier de cette forme créé ou modifié depuis Since est masqué sur place
        (Protect-OpLogFile, encodage d'origine conservé), puis copié dans Destination s'il est fourni. La copie n'a
        lieu qu'après un masquage réussi. Ne lève jamais d'erreur : la fonction s'exécute dans le bloc finally de
        l'étape Office et ne doit pas masquer l'erreur d'origine ; chaque échec est journalisé.
        Renvoie un objet par fichier (Path, Replacements, Copied, Error, ReportNote). En cas d'échec du masquage,
        ReportNote porte la mention du rapport « journal ODT non masqué resté dans TEMP : <chemin complet> », pour
        suppression manuelle avant de rendre le PC (8.5, 8.8).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [Parameter(Mandatory)][string[]]$SearchDirectory,
        [string]$ProductKey,
        [string]$Destination,
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $namePattern = '^' + [regex]::Escape($ComputerName) + '-\d{8}-\d{4}\.log$'
    $files = @(foreach ($directory in $SearchDirectory) {
            if (-not $directory -or -not (Test-Path -Path $directory -PathType Container)) { continue }
            Get-ChildItem -Path $directory -File -Filter '*.log' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $namePattern -and $_.LastWriteTime -ge $Since }
        }) | Sort-Object FullName -Unique

    foreach ($file in $files) {
        $result = [pscustomobject]@{ Path = $file.FullName; Replacements = 0; Copied = $false; Error = $null; ReportNote = $null }
        $masked = $false
        try {
            $result.Replacements = Protect-OpLogFile -Path $file.FullName -ProductKey $ProductKey -ErrorAction Stop
            $masked = $true
            if ($Destination -and $PSCmdlet.ShouldProcess($Destination, "Copie de $($file.Name)")) {
                New-Item -ItemType Directory -Force -Path $Destination -ErrorAction Stop | Out-Null
                Copy-Item -Path $file.FullName -Destination (Join-Path $Destination $file.Name) -Force -ErrorAction Stop
                $result.Copied = $true
            }
            Write-OpLog ("Journal de l'ODT masqué ({0} remplacement(s)) : {1}" -f $result.Replacements, $file.Name) -Level DEBUG
        } catch {
            $result.Error = $_.Exception.Message
            if (-not $masked) {
                $result.ReportNote = "journal ODT non masqué resté dans TEMP : $($file.FullName)"
                Write-OpLog ("Journal de l'ODT non masqué, non copié, à supprimer à la main avant de rendre le PC : {0} : {1}" -f $file.FullName, $_.Exception.Message) -Level ERROR
            } else {
                Write-OpLog ("Journal de l'ODT masqué mais non copié dans la session : {0} : {1}" -f $file.FullName, $_.Exception.Message) -Level WARN
            }
        }
        $result
    }
}
