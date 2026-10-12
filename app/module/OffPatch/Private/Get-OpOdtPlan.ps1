function Get-OpOdtPlan {
    <#
    .SYNOPSIS
        Lit sur la page officielle le lien de la dernière version de l'ODT et la compare au setup.exe de tools\odt.

    .DESCRIPTION
        Lecture seule (cahier des charges 7.1, R-07). La page downloadPages.officeDeploymentToolPage du Centre de
        téléchargement contient le lien direct officedeploymenttool_<a>-<b>.exe, dont le nom porte la version de
        setup.exe (16.0.<a>.<b>, relevé en R-07). L'ODT est à jour quand le setup.exe de tools\odt a une version
        égale ou supérieure : rien n'est alors résolu ni téléchargé. Sinon, le lien est résolu par requêtes HEAD
        (Resolve-OpDownloadUrl, hôtes de allowedDomains) pour l'URL finale et la taille.
        Une erreur (page illisible, lien introuvable, hôte refusé) est portée par la propriété Error, sans exception.
        Renvoie FileName, Url, Version, InstalledVersion ($null sans ODT), SetupPath, UpToDate, SizeBytes, Hosts,
        Error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][string]$Root
    )

    $setup = Join-Path (Get-OpPath -Name Odt -Root $Root) 'setup.exe'
    $installed = $null
    if (Test-Path -LiteralPath $setup -PathType Leaf) { $installed = Get-OpFileVersion -Path $setup }
    $plan = [pscustomobject]@{
        FileName         = $null
        Url              = $null
        Version          = $null
        InstalledVersion = $installed
        SetupPath        = $setup
        UpToDate         = $false
        SizeBytes        = $null
        Hosts            = @()
        Error            = $null
    }

    $page = [string]$Configuration.Settings.downloadPages.officeDeploymentToolPage
    $allowed = @($Configuration.Settings.allowedDomains)
    $pageHost = ([uri]$page).Host
    if ($allowed -notcontains $pageHost) {
        $plan.Error = "Page de l'ODT refusée : hôte $pageHost absent de allowedDomains ($page)."
        return $plan
    }
    try {
        $html = Invoke-OpWebRequest -Uri $page
    } catch {
        $plan.Error = "Page de l'ODT illisible ($page) : $($_.Exception.Message)"
        return $plan
    }

    # Plusieurs liens possibles (page dupliquée pour l'affichage) : la version la plus élevée l'emporte.
    $link = [regex]::Matches($html, '(?i)https?://[^"''\s<>\\]+/(officedeploymenttool_(\d+)-(\d+)\.exe)') |
        Sort-Object -Property { [version]('16.0.{0}.{1}' -f $_.Groups[2].Value, $_.Groups[3].Value) } |
        Select-Object -Last 1
    if (-not $link) {
        $plan.Error = "Lien officedeploymenttool_<version>.exe introuvable sur la page de l'ODT ($page) : structure de la page inconnue."
        return $plan
    }
    $plan.FileName = $link.Groups[1].Value
    $plan.Url = $link.Value
    $plan.Version = [version]('16.0.{0}.{1}' -f $link.Groups[2].Value, $link.Groups[3].Value)
    if ($null -ne $installed -and $installed -ge $plan.Version) {
        $plan.UpToDate = $true
        return $plan
    }

    try {
        $resolved = Resolve-OpDownloadUrl -Url $plan.Url -AllowedDomain $allowed
    } catch {
        $plan.Error = $_.Exception.Message
        return $plan
    }
    $plan.Url = $resolved.Url
    $plan.Hosts = @($resolved.Hosts)
    $plan.SizeBytes = $resolved.SizeBytes
    $plan
}
