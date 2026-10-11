function Get-OpDefenderDefinitionPlan {
    <#
    .SYNOPSIS
        Élément « définitions Defender » (mpam-fe.exe) d'une cible pour la liste de la mise à jour du dépôt.

    .DESCRIPTION
        Lecture seule (cahier des charges 7.1, R-06). Le lien officiel de l'architecture de la cible
        (downloadPages.defenderDefinitions de settings.json) est résolu par Resolve-OpDownloadUrl : requêtes HEAD,
        hôtes contrôlés par allowedDomains. L'URL finale porte la version des définitions (packageVersion) et
        l'architecture (arch), ce qui permet de savoir si le dépôt est à jour sans rien télécharger.
        Le fichier est « au dépôt » quand le manifeste contient un élément defender de la même architecture et de
        la même version ; son nom, mpam-fe.exe, ne change jamais et ne peut pas servir de repère.
        Lien refusé, version absente de l'URL finale ou architecture différente : l'erreur est portée par le fichier,
        sans arrêter la liste. Renvoie un objet de même forme que les éléments de Get-OpDepotPlan.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][string]$Target
    )

    $arch = ($Target -split '-')[1]
    $url = [string]$Configuration.Settings.downloadPages.defenderDefinitions.$arch
    $file = [pscustomobject]@{
        FileName  = 'mpam-fe.exe'
        Url       = $url
        Sha1      = $null
        SizeBytes = $null
        Hosts     = @()
        InDepot   = $false
        Error     = $null
    }
    $item = [pscustomobject]@{
        Id            = "$Target-defender"
        Target        = $Target
        Category      = 'defender'
        Source        = 'link'
        Kb            = $null
        Title         = "Définitions Microsoft Defender ($arch)"
        Version       = $null
        ResultingUbr  = $null
        BaseBuilds    = @()
        Prerequisites = @()
        RunsAfter     = @('defender-platform')
        ReleaseDate   = $null
        Files         = @($file)
        Warnings      = @()
    }

    try {
        $resolved = Resolve-OpDownloadUrl -Url $url -AllowedDomain @($Configuration.Settings.allowedDomains)
    } catch {
        $file.Error = $_.Exception.Message
        return $item
    }
    $file.Url = $resolved.Url
    $file.Hosts = @($resolved.Hosts)
    $file.SizeBytes = $resolved.SizeBytes

    # Forme relevée en R-06 : …/mpam-fe.exe?packageType=Signatures&packageVersion=1.459.553.0&arch=amd64&…
    $query = ([uri]$resolved.Url).Query
    $versionMatch = [regex]::Match($query, '(?i)[?&]packageVersion=(\d+(\.\d+){1,3})(&|$)')
    $archMatch = [regex]::Match($query, '(?i)[?&]arch=([a-z0-9]+)(&|$)')
    $expectedArch = @{ x64 = 'amd64'; arm64 = 'arm64' }[$arch]
    if (-not $versionMatch.Success) {
        $file.Error = "Version des définitions absente du lien final : $($resolved.Url)"
        return $item
    }
    if (-not $archMatch.Success -or $archMatch.Groups[1].Value.ToLowerInvariant() -ne $expectedArch) {
        $file.Error = "Le lien final ne désigne pas l'architecture $arch (arch=$expectedArch attendu) : $($resolved.Url)"
        return $item
    }

    $version = [version]$versionMatch.Groups[1].Value
    $item.Version = $version
    $item.Id = "$Target-defender-$version"
    foreach ($m in @($Manifest.items)) {
        if ($m.category -ne 'defender' -or $null -eq $m.PSObject.Properties['version'] -or $null -eq $m.PSObject.Properties['target']) { continue }
        if ($m.target.arch -eq $arch -and [string]$m.version -eq [string]$version) { $file.InDepot = $true }
    }
    $item
}
