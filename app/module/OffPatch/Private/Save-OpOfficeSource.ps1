function Save-OpOfficeSource {
    <#
    .SYNOPSIS
        Télécharge ou complète une source Office du dépôt par setup.exe /download, puis relève la version obtenue.

    .DESCRIPTION
        Cahier des charges 7.1. Le XML de la source (Get-OpOfficeDownloadXml) est écrit dans depot\.tmp, puis
        setup.exe de tools\odt est lancé en mode download par Invoke-OpOfficeSetup, qui supprime le XML et copie les
        journaux de l'ODT (TEMP de l'utilisateur) dans le dossier du journal du dépôt. Le trafic de l'ODT vers ses
        propres domaines n'est pas soumis à allowedDomains (6.1). L'ODT ajoute la nouvelle version à côté de
        l'ancienne (R-07) : la purge s'en charge ensuite. Un code retour non nul, un délai dépassé ou une source
        sans version lisible lèvent une erreur.
        Renvoie Id, Channel, Languages, SourcePath, PreviousVersion ($null pour une source nouvelle), Version,
        FromIndex (version lue dans v64.cab), Updated, DurationSeconds.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Source,
        [Parameter(Mandatory)][string]$SetupPath,
        [Parameter(Mandatory)][string]$Root,
        # ponytail: délai fixe pour environ 4 Go par source ; à rendre réglable si une connexion lente le dépasse.
        [ValidateRange(1, 1440)][int]$TimeoutMinutes = 240
    )

    if (-not $PSCmdlet.ShouldProcess($Source.SourcePath, "Téléchargement de la source Office $($Source.Id) (setup.exe /download)")) { return }
    if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) { throw "Source Office $($Source.Id) non téléchargée : setup.exe absent de $(Split-Path -Path $SetupPath -Parent)." }

    $temp = Get-OpPath -Name DepotTemp -Root $Root
    $work = Join-Path $temp "office-$($Source.Id)"
    $before = Get-OpOfficeSourceVersion -Path $Source.SourcePath -WorkFolder $work
    New-Item -ItemType Directory -Force -Path $Source.SourcePath, $temp -ErrorAction Stop | Out-Null
    $config = Join-Path $temp "office-$($Source.Id).xml"
    [System.IO.File]::WriteAllText($config, $Source.Xml, (New-Object System.Text.UTF8Encoding $false))

    $logDirectory = $null
    $log = Get-Variable -Name OpLog -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($log -and $log.Path) { $logDirectory = [System.IO.Path]::ChangeExtension($log.Path, $null) }

    Write-OpLog "Source Office $($Source.Id) ($($Source.Channel), $(@($Source.Languages) -join ', ')) : setup.exe /download vers $($Source.SourcePath)."
    $start = Get-Date
    $run = Invoke-OpOfficeSetup -SetupPath $SetupPath -ConfigPath $config -Mode download -TimeoutMinutes $TimeoutMinutes -LogSearchDirectory @($env:TEMP) -SessionLogDirectory $logDirectory -StepStart $start.AddMinutes(-1) -Confirm:$false
    $seconds = [int]((Get-Date) - $start).TotalSeconds
    if ($run.TimedOut) { throw "Source Office $($Source.Id) : setup.exe /download a dépassé le délai de $TimeoutMinutes min." }
    if ($run.ExitCode -ne 0) { throw "Source Office $($Source.Id) : setup.exe /download a renvoyé le code $($run.ExitCode), voir les journaux de l'ODT." }

    $after = Get-OpOfficeSourceVersion -Path $Source.SourcePath -WorkFolder $work
    if (-not $after) { throw "Source Office $($Source.Id) : aucune version dans $($Source.SourcePath)\Office\Data après setup.exe /download." }
    if (-not $after.FromIndex) { Write-OpLog -Level WARN -Message "Source Office $($Source.Id) : v64.cab absent, version la plus élevée retenue ($($after.Version))." }
    $previous = $null
    if ($before) { $previous = $before.Version }
    $updated = ($null -eq $previous) -or ($after.Version -ne $previous)
    if ($updated) { Write-OpLog "Source Office $($Source.Id) : version $($after.Version) obtenue en $seconds s (précédente : $(if ($previous) { $previous } else { 'aucune' }))." }
    else { Write-OpLog "Source Office $($Source.Id) : déjà à jour en version $($after.Version) ($seconds s)." }

    [pscustomobject]@{
        Id              = $Source.Id
        Channel         = $Source.Channel
        Languages       = @($Source.Languages)
        SourcePath      = $Source.SourcePath
        PreviousVersion = $previous
        Version         = $after.Version
        FromIndex       = $after.FromIndex
        Updated         = $updated
        DurationSeconds = $seconds
    }
}
