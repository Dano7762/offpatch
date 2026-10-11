function ConvertTo-OpManifestItem {
    <#
    .SYNOPSIS
        Construit l'élément du manifeste (cahier des charges 7.2) à partir d'un élément de Get-OpDepotPlan et des
        entrées de fichier rangées au dépôt.

    .DESCRIPTION
        Fonction pure. Cible : os et arch tirés du nom de la cible ; minBuild et maxBuild seulement quand les builds
        de base sont connues. Ordre et redémarrage par catégorie, selon l'ordre par défaut du plan (8.3) :
        plateforme Defender, définitions, SSU, checkpoint, cumulative, enablement package, .NET. Un élément épinglé
        reprend ses conditions de pinned-items.json (minUbr, resultingBuild, applyBelowUbr). Fichiers .NET Windows 10 :
        plage netRelease selon ndp48 ou ndp481 (R-05). Cumulative Windows 10 : la version du paquet lue dans le .msu
        contre-vérifie resultingUbr (deuxième nombre, 19041.<UBR>.1.0, R-09) ; en cas d'écart, avertissement et la
        valeur du .msu fait foi.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files,
        [Parameter(Mandatory)][pscustomobject]$Configuration
    )

    $order = @{ 'defender-platform' = 10; 'defender' = 11; 'windows-ssu' = 18; 'windows-checkpoint' = 19; 'windows-lcu' = 20; 'windows-ekb' = 30; 'dotnet' = 40 }
    $reboot = @{ 'windows-checkpoint' = $true; 'windows-lcu' = $true; 'windows-ekb' = $true }
    $os, $arch = $Item.Target -split '-', 2

    $target = [ordered]@{ os = $os; arch = $arch }
    $baseBuilds = @($Item.BaseBuilds | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
    if ($baseBuilds.Count -gt 0) {
        $target.minBuild = ($baseBuilds | Measure-Object -Minimum).Minimum
        $target.maxBuild = ($baseBuilds | Measure-Object -Maximum).Maximum
    }

    $entries = @(foreach ($f in $Files) {
            $entry = [ordered]@{ path = $f.path; sha256 = $f.sha256; size = [long]$f.size }
            if ($null -ne $f.PSObject.Properties['package'] -and $f.package) { $entry.package = [ordered]@{ name = $f.package.name; version = $f.package.version } }
            if ($Item.Category -eq 'dotnet' -and $os -eq 'win10') {
                # Valeur Release de .NET Framework 4 : 4.8 de 528040 à 533319, 4.8.1 à partir de 533320 (R-05).
                if ($f.path -match '(?i)-ndp481_') { $entry.netRelease = [ordered]@{ min = 533320 } }
                elseif ($f.path -match '(?i)-ndp48_') { $entry.netRelease = [ordered]@{ min = 528040; max = 533319 } }
            }
            [pscustomobject]$entry
        })

    $resultingUbr = $Item.ResultingUbr
    if ($Item.Category -eq 'windows-lcu' -and $os -eq 'win10') {
        $package = @($entries | Where-Object { $null -ne $_.PSObject.Properties['package'] } | ForEach-Object { $_.package }) | Select-Object -First 1
        $packageVersion = $null
        if ($package -and [version]::TryParse([string]$package.version, [ref]$packageVersion) -and $packageVersion.Minor -ne [int]$resultingUbr) {
            Write-OpLog -Level WARN -Message "Dépôt, $($Item.Id) : UBR $resultingUbr annoncé par release-information, $($packageVersion.Minor) lu dans le .msu ($($package.version)) ; la valeur du .msu fait foi."
            $resultingUbr = $packageVersion.Minor
        }
    }

    $m = [ordered]@{ id = $Item.Id; category = $Item.Category; target = [pscustomobject]$target }
    if ($Item.Kb) { $m.kb = $Item.Kb }
    if ($Item.Title) { $m.title = $Item.Title }
    if ($Item.ReleaseDate) {
        if ($Item.ReleaseDate -is [datetime]) { $m.releaseDate = $Item.ReleaseDate.ToString('yyyy-MM-dd') } else { $m.releaseDate = [string]$Item.ReleaseDate }
    }
    if ($null -ne $Item.Version) { $m.version = [string]$Item.Version }
    if ($baseBuilds.Count -gt 0) { $m.baseBuilds = $baseBuilds }
    if ($null -ne $resultingUbr) { $m.resultingUbr = [int]$resultingUbr }
    if ($Item.Source -eq 'pinned') {
        $pinned = @($Configuration.PinnedItems.items | Where-Object { $_.id -eq $Item.Id }) | Select-Object -First 1
        foreach ($field in 'minUbr', 'resultingBuild', 'applyBelowUbr') {
            if ($pinned -and $null -ne $pinned.PSObject.Properties[$field]) { $m[$field] = $pinned.$field }
        }
    }
    $m.order = $order[$Item.Category]
    $m.requiresReboot = [bool]$reboot[$Item.Category]
    $m.prerequisites = @($Item.Prerequisites | Where-Object { $_ })
    $m.runsAfter = @($Item.RunsAfter | Where-Object { $_ })
    $m.files = $entries
    [pscustomobject]$m
}
