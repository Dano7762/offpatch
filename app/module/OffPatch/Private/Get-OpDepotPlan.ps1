function Get-OpDepotPlan {
    <#
    .SYNOPSIS
        Établit la liste des éléments que la mise à jour du dépôt récupérerait, sans rien télécharger.

    .DESCRIPTION
        Lecture seule (cahier des charges 7.1, étapes 2 à 4, et option -ListOnly). Pour chaque cible de settings.json :
          - éléments du catalogue : sélection par Get-OpCatalogSelection, puis liens de l'entrée retenue par la
            fenêtre de téléchargement (Get-OpCatalogDownloadLink) ; fileNamePattern choisit le fichier quand il est
            défini ; quand un fichier porte le KB retenu, les autres fichiers de l'entrée sont ses prérequis joints
            (cumulative checkpoint, R-02) et deviennent un élément de la catégorie windows-checkpoint ;
          - éléments épinglés de pinned-items.json dont l'identifiant commence par la cible (l'enablement package
            seulement si windows.includeEnablementPackage est vrai) ;
          - définitions Defender (mpam-fe.exe) de l'architecture de la cible, par Get-OpDefenderDefinitionPlan.
        Un fichier est « au dépôt » quand le manifeste contient déjà un fichier du même nom : le nom porte le SHA-1
        publié par Microsoft. Les autres liens sont résolus par Resolve-OpDownloadUrl (requêtes HEAD, hôtes contrôlés
        par allowedDomains, taille annoncée), un lien par URL. Un lien refusé ou inaccessible n'arrête pas la liste :
        l'erreur est portée par le fichier.
        Renvoie un objet par élément (Id, Target, Category, Source, Kb, Title, Version, ResultingUbr, BaseBuilds,
        Prerequisites, RunsAfter, ReleaseDate, Files, Warnings) ; chaque fichier porte FileName, Url, Sha1,
        SizeBytes, Hosts, InDepot et Error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [datetime]$Now = (Get-Date)
    )

    $settings = $Configuration.Settings
    $allowed = @($settings.allowedDomains)

    # Noms des fichiers déjà au dépôt (files/<sha256>/<nom d'origine>).
    $depotNames = @{}
    foreach ($item in @($Manifest.items)) {
        if ($null -eq $item.PSObject.Properties['files']) { continue }
        foreach ($f in @($item.files)) {
            if ($f -and $f.path) { $depotNames[([string]$f.path -split '[\\/]')[-1].ToLowerInvariant()] = $true }
        }
    }

    $resolved = @{}
    function Get-PlanFile([string]$Name, [string]$Url, [string]$Sha1) {
        $file = [pscustomobject]@{
            FileName  = $Name
            Url       = $Url
            Sha1      = $Sha1
            SizeBytes = $null
            Hosts     = @()
            InDepot   = $depotNames.ContainsKey($Name.ToLowerInvariant())
            Error     = $null
        }
        if (-not $file.InDepot) {
            if (-not $resolved.ContainsKey($Url)) {
                try {
                    $resolved[$Url] = Resolve-OpDownloadUrl -Url $Url -AllowedDomain $allowed
                } catch {
                    $resolved[$Url] = $_.Exception.Message
                }
            }
            $r = $resolved[$Url]
            if ($r -is [string]) {
                $file.Error = $r
            } else {
                $file.Url = $r.Url
                $file.Hosts = @($r.Hosts)
                $file.SizeBytes = $r.SizeBytes
            }
        }
        $file
    }
    function Get-PlanItem([string]$Id, [string]$Target, [string]$Category, [string]$Source, [string]$Kb, [string]$Title, [object[]]$Files) {
        [pscustomobject]@{
            Id            = $Id
            Target        = $Target
            Category      = $Category
            Source        = $Source
            Kb            = $Kb
            Title         = $Title
            Version       = $null
            ResultingUbr  = $null
            BaseBuilds    = @()
            Prerequisites = @()
            RunsAfter     = @()
            ReleaseDate   = $null
            Files         = @($Files)
            Warnings      = @()
        }
    }

    foreach ($target in @($settings.targets)) {
        foreach ($selection in @(Get-OpCatalogSelection -Configuration $Configuration -Target $target -Now $Now)) {
            if (-not $selection.Kb) { continue }
            $warnings = New-Object System.Collections.Generic.List[string]
            $links = @(Get-OpCatalogDownloadLink -UpdateId $selection.UpdateId)
            if ($selection.FileNamePattern) {
                $links = @($links | Where-Object { $_.FileName -match $selection.FileNamePattern })
                if ($links.Count -eq 0) {
                    $warnings.Add("aucun fichier de l'entrée ne correspond à fileNamePattern.")
                    Write-OpLog -Level WARN -Message "Catalogue, $target / $($selection.Category) : aucun fichier de $($selection.Kb) ne correspond à fileNamePattern."
                }
            }
            # Fichier principal : celui qui porte le KB retenu ; les autres fichiers sont des prérequis joints (R-02).
            $kbToken = $selection.Kb.ToLowerInvariant()
            $main = @($links | Where-Object { $_.FileName.ToLowerInvariant() -match ('(^|[^a-z0-9])' + $kbToken + '([^0-9]|$)') })
            $joined = @()
            if ($main.Count -gt 0) { $joined = @($links | Where-Object { $main -notcontains $_ }) } else { $main = $links }

            $short = $selection.Category -replace '^windows-', ''
            $id = '{0}-{1}-{2}' -f $target, $short, $selection.Kb
            if ($selection.Pick -eq 'highestVersion' -and $selection.Version) { $id = '{0}-{1}-{2}' -f $target, $short, $selection.Version }
            $item = Get-PlanItem -Id $id -Target $target -Category $selection.Category -Source 'catalog' -Kb $selection.Kb -Title $selection.Title `
                -Files @(foreach ($l in $main) { Get-PlanFile -Name $l.FileName -Url $l.Url -Sha1 $l.Sha1 })
            $item.Version = $selection.Version
            $item.ResultingUbr = $selection.ResultingUbr
            $item.BaseBuilds = @($selection.BaseBuilds)
            $item.Prerequisites = @($selection.Prerequisites)
            $item.RunsAfter = @($selection.RunsAfter)
            $item.ReleaseDate = $selection.ReleaseDate
            $item.Warnings = @($selection.Warnings) + $warnings.ToArray()
            $item

            foreach ($j in $joined) {
                $jkb = [regex]::Match($j.FileName, '(?i)kb(\d+)')
                $category = 'windows-checkpoint'
                if (@($selection.Prerequisites) -notcontains 'windows-checkpoint') {
                    Write-OpLog -Level WARN -Message "Catalogue, $target : fichier joint « $($j.FileName) » à $($selection.Kb), sans prérequis windows-checkpoint déclaré ; classé en windows-checkpoint."
                }
                $jid = '{0}-checkpoint-{1}' -f $target, $(if ($jkb.Success) { 'KB' + $jkb.Groups[1].Value } else { $j.Sha1 })
                $title = "Prérequis joint à « $($selection.Title) »"
                Get-PlanItem -Id $jid -Target $target -Category $category -Source 'catalog' -Kb $(if ($jkb.Success) { 'KB' + $jkb.Groups[1].Value } else { $null }) -Title $title `
                    -Files @(Get-PlanFile -Name $j.FileName -Url $j.Url -Sha1 $j.Sha1)
            }
        }

        foreach ($pinned in @($Configuration.PinnedItems.items | Where-Object { ([string]$_.id).StartsWith($target + '-') })) {
            if ($pinned.category -eq 'windows-ekb' -and -not $settings.windows.includeEnablementPackage) { continue }
            $name = ([uri]$pinned.url).Segments[-1]
            $item = Get-PlanItem -Id $pinned.id -Target $target -Category $pinned.category -Source 'pinned' -Kb $pinned.kb -Title "Élément épinglé $($pinned.id)" `
                -Files @(Get-PlanFile -Name $name -Url $pinned.url -Sha1 $pinned.sha1)
            $item.BaseBuilds = @($pinned.appliesToBaseBuilds)
            if ($null -ne $pinned.PSObject.Properties['prerequisites']) { $item.Prerequisites = @($pinned.prerequisites) }
            if ($null -ne $pinned.PSObject.Properties['runsAfter']) { $item.RunsAfter = @($pinned.runsAfter) }
            $item
        }

        Get-OpDefenderDefinitionPlan -Configuration $Configuration -Manifest $Manifest -Target $target
    }
}
