function Save-OpOdt {
    <#
    .SYNOPSIS
        Télécharge la version de l'ODT donnée par Get-OpOdtPlan, la vérifie et range son setup.exe dans tools\odt.

    .DESCRIPTION
        Cahier des charges 7.1, R-07. Le fichier officedeploymenttool_<version>.exe est téléchargé dans
        depot\.tmp\odt (Save-OpDownload, taille contrôlée), sa signature est vérifiée (Confirm-OpDownloadIntegrity),
        puis il est extrait sans interface (/quiet /extract:, mesuré en R-07). L'exécutable demande
        requireAdministrator : sans droits d'administrateur, erreur avant tout téléchargement. Le setup.exe extrait est vérifié à
        son tour, puis remplace celui de tools\odt (copie à côté, puis renommage). Une version de setup.exe
        différente de celle annoncée par le nom du fichier est signalée dans le journal, sans refus.
        Rien n'est exécuté ni téléchargé quand le plan est à jour ; un plan en erreur lève cette erreur.
        Le dossier de travail n'est supprimé qu'après réussite : un téléchargement interrompu reprend au lancement
        suivant. Renvoie Version (de setup.exe) et Path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan,
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][string]$Root,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300
    )

    if ($Plan.Error) { throw "ODT non mis à jour : $($Plan.Error)" }
    if ($Plan.UpToDate) { return [pscustomobject]@{ Version = $Plan.InstalledVersion; Path = $Plan.SetupPath } }
    if (-not $PSCmdlet.ShouldProcess($Plan.SetupPath, "Mise à jour de l'ODT en version $($Plan.Version)")) { return }
    if (-not (Test-OpElevated)) {
        throw "ODT non mis à jour : son extraction exige les droits d'administrateur (requireAdministrator). Lancer OffPatch par Lancer-OffPatch.cmd ou depuis une console élevée."
    }

    $trusted = @($Configuration.Settings.integrity.trustedRootThumbprints)
    $work = Join-Path (Get-OpPath -Name DepotTemp -Root $Root) 'odt'
    $exe = Join-Path $work $Plan.FileName
    $extract = Join-Path $work 'extract'

    Save-OpDownload -Url $Plan.Url -Destination $exe -ExpectedSize $Plan.SizeBytes -Confirm:$false | Out-Null
    Confirm-OpDownloadIntegrity -Path $exe -TrustedRootThumbprint $trusted -Confirm:$false | Out-Null
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction Stop }
    $run = Invoke-OpProcess -FilePath $exe -ArgumentList '/quiet', "/extract:$extract" -TimeoutSeconds $TimeoutSeconds -Confirm:$false -ErrorAction Stop
    if ($run.TimedOut) { throw "Extraction de $($Plan.FileName) : délai de $TimeoutSeconds s dépassé." }
    if ($run.ExitCode -ne 0) { throw "Extraction de $($Plan.FileName) : code retour $($run.ExitCode)." }
    $newSetup = Join-Path $extract 'setup.exe'
    if (-not (Test-Path -LiteralPath $newSetup -PathType Leaf)) { throw "Extraction de $($Plan.FileName) : setup.exe absent." }
    Confirm-OpDownloadIntegrity -Path $newSetup -TrustedRootThumbprint $trusted -Confirm:$false | Out-Null
    $version = Get-OpFileVersion -Path $newSetup
    if ([string]$version -ne [string]$Plan.Version) {
        Write-OpLog -Level WARN -Message "ODT : setup.exe en version $version, $($Plan.Version) annoncée par $($Plan.FileName)."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Path $Plan.SetupPath -Parent) -ErrorAction Stop | Out-Null
    $staging = $Plan.SetupPath + '.new'
    Copy-Item -LiteralPath $newSetup -Destination $staging -Force -ErrorAction Stop
    Move-Item -LiteralPath $staging -Destination $Plan.SetupPath -Force -ErrorAction Stop
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Write-OpLog "ODT mis à jour : setup.exe $version ($($Plan.FileName))."
    [pscustomobject]@{ Version = $version; Path = $Plan.SetupPath }
}
