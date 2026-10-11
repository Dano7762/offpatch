function Select-OpCatalogUpdate {
    <#
    .SYNOPSIS
        Applique une entrée de catalog-queries.json (motifs et règle de sélection) aux lignes renvoyées par le catalogue.

    .DESCRIPTION
        Fonction pure, sans accès réseau (cahier des charges 6.2). Garde les titres qui passent le motif d'inclusion
        et pas celui d'exclusion, les regroupe par KB, puis choisit un groupe selon la règle pick :
          - highestUbr : UBR le plus élevé, dernier nombre du titre ; BaseBuilds réunit les builds des titres du
            groupe (une entrée par version, mêmes fichiers, R-01) ;
          - highestUbrFromReleaseInformation : UBR tiré de ReleaseInformation (KB → UBR) ; si aucun KB candidat
            n'y figure, repli sur latestMonth avec un avertissement ;
          - latestMonth : préfixe AAAA-MM du titre le plus récent ; la date du catalogue ne départage deux KB du
            même mois qu'avec un avertissement ;
          - highestVersion : version la plus élevée citée dans le titre (« (Version 4.18.x.y) »).
        Renvoie un seul objet : KB choisi (Kb à $null si rien ne convient), entrée représentative (UpdateId, Title),
        toutes les entrées du groupe, BaseBuilds, ResultingUbr, Version, Month, champs recopiés de l'entrée
        (prerequisites, runsAfter, fileNamePattern) et la liste des avertissements, à journaliser par l'appelant.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Item,
        [Parameter(Mandatory)][pscustomobject]$Entry,
        [System.Collections.Generic.Dictionary[string, int]]$ReleaseInformation
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $label = "$($Entry.category) ($($Entry.pick))"

    # Lignes retenues par les motifs, avec les valeurs lues dans le titre.
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($i in $Item) {
        if ($i.Title -notmatch $Entry.includeTitlePattern -or $i.Title -match $Entry.excludeTitlePattern) { continue }
        $kb = [regex]::Match($i.Title, '\b(KB\d+)\b')
        if (-not $kb.Success) { $warnings.Add("$label : titre sans numéro de KB écarté : « $($i.Title) ».") ; continue }
        $month = [regex]::Match($i.Title, '^(\d{4}-\d{2}) ')
        $buildUbr = [regex]::Match($i.Title, '\((\d{5})\.(\d+)\)$')
        $version = [regex]::Match($i.Title, '\(Version (\d+(\.\d+){1,3})\)')
        $candidates.Add([pscustomobject]@{
                Item    = $i
                Kb      = $kb.Groups[1].Value
                Month   = $(if ($month.Success) { $month.Groups[1].Value } else { $null })
                Build   = $(if ($buildUbr.Success) { [int]$buildUbr.Groups[1].Value } else { $null })
                Ubr     = $(if ($buildUbr.Success) { [int]$buildUbr.Groups[2].Value } else { $null })
                Version = $(if ($version.Success) { [version]$version.Groups[1].Value } else { $null })
            })
    }

    $pick = $Entry.pick
    if ($pick -eq 'highestUbrFromReleaseInformation') {
        $known = @($candidates | Where-Object { $ReleaseInformation -and $ReleaseInformation.ContainsKey($_.Kb) })
        if ($candidates.Count -gt 0 -and $known.Count -eq 0) {
            $warnings.Add("$label : aucun KB candidat ($((@($candidates | ForEach-Object { $_.Kb } | Sort-Object -Unique)) -join ', ')) ne figure dans la page release-information ; sélection par le mois du titre, UBR inconnu.")
            $pick = 'latestMonth'
        } else {
            foreach ($c in $known) { $c.Ubr = $ReleaseInformation[$c.Kb] }
            $candidates = $known
        }
    }
    if ($pick -eq 'highestUbr') {
        foreach ($c in @($candidates | Where-Object { $null -eq $_.Ubr })) { $warnings.Add("$label : titre sans build ni UBR écarté : « $($c.Item.Title) ».") }
        $candidates = @($candidates | Where-Object { $null -ne $_.Ubr })
    }
    if ($pick -eq 'latestMonth') {
        foreach ($c in @($candidates | Where-Object { $null -eq $_.Month })) { $warnings.Add("$label : titre sans mois AAAA-MM écarté : « $($c.Item.Title) ».") }
        $candidates = @($candidates | Where-Object { $null -ne $_.Month })
    }
    if ($pick -eq 'highestVersion') {
        foreach ($c in @($candidates | Where-Object { $null -eq $_.Version })) { $warnings.Add("$label : titre sans version écarté : « $($c.Item.Title) ».") }
        $candidates = @($candidates | Where-Object { $null -ne $_.Version })
    }

    # Un groupe par KB (par KB et version pour highestVersion : la plateforme Defender garde le même KB).
    $groups = @($candidates | Group-Object -Property { if ($pick -eq 'highestVersion') { "$($_.Kb) $($_.Version)" } else { $_.Kb } } | ForEach-Object {
            $members = @($_.Group)
            $ubrs = @($members | Where-Object { $null -ne $_.Ubr } | ForEach-Object { $_.Ubr } | Sort-Object -Unique)
            if ($ubrs.Count -gt 1) { $warnings.Add("$label : $($members[0].Kb) cité avec plusieurs UBR ($($ubrs -join ', ')) ; le plus élevé est retenu.") }
            $dates = @($members | Where-Object { $_.Item.LastUpdated } | ForEach-Object { $_.Item.LastUpdated } | Sort-Object -Descending)
            # Titres sans mois (plateforme Defender) : liste vide, jamais indexée sous StrictMode.
            $groupMonths = @($members | Where-Object { $null -ne $_.Month } | ForEach-Object { $_.Month } | Sort-Object -Descending)
            [pscustomobject]@{
                Kb          = $members[0].Kb
                Members     = @($members | Sort-Object -Property { $_.Item.Title })
                Ubr         = $(if ($ubrs.Count -gt 0) { $ubrs[-1] } else { $null })
                Month       = $(if ($groupMonths.Count -gt 0) { $groupMonths[0] } else { $null })
                Version     = $members[0].Version
                LastUpdated = $(if ($dates.Count -gt 0) { $dates[0] } else { $null })
            }
        })

    $chosen = $null
    if ($groups.Count -gt 0) {
        $byDate = @{ Expression = { if ($_.LastUpdated) { $_.LastUpdated } else { [datetime]::MinValue } }; Descending = $true }
        switch ($pick) {
            'highestUbr' { $sorted = @($groups | Sort-Object -Property @{ Expression = 'Ubr'; Descending = $true }, @{ Expression = 'Month'; Descending = $true }, $byDate) }
            'highestUbrFromReleaseInformation' { $sorted = @($groups | Sort-Object -Property @{ Expression = 'Ubr'; Descending = $true }, @{ Expression = 'Month'; Descending = $true }, $byDate) }
            'latestMonth' { $sorted = @($groups | Sort-Object -Property @{ Expression = 'Month'; Descending = $true }, $byDate) }
            'highestVersion' { $sorted = @($groups | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, $byDate) }
            default { throw "$label : règle de sélection inconnue." }
        }
        $chosen = $sorted[0]
        if ($sorted.Count -gt 1) {
            # Pas de switch ici : il redéfinirait $_.
            if ($pick -eq 'latestMonth') { $tied = @($sorted | Where-Object { $_.Month -eq $chosen.Month }) }
            elseif ($pick -eq 'highestVersion') { $tied = @($sorted | Where-Object { $_.Version -eq $chosen.Version }) }
            else { $tied = @($sorted | Where-Object { $_.Ubr -eq $chosen.Ubr }) }
            if ($tied.Count -gt 1) {
                $warnings.Add("$label : $($tied.Count) KB à égalité ($(($tied | ForEach-Object { $_.Kb }) -join ', ')) ; $($chosen.Kb) retenu d'après la date du catalogue.")
            }
        }
    } else {
        $warnings.Add("$label : aucune entrée du catalogue ne correspond aux motifs.")
    }

    $representative = $null
    if ($chosen) { $representative = $chosen.Members[0].Item }
    $baseBuilds = @()
    if ($chosen -and $Entry.pick -eq 'highestUbr') { $baseBuilds = @($chosen.Members | ForEach-Object { $_.Build } | Sort-Object -Unique) }
    elseif ($chosen -and $Entry.pick -eq 'highestUbrFromReleaseInformation') { $baseBuilds = @([int]$Entry.releaseInformationBuild) }
    $resultingUbr = $null
    if ($chosen -and @('highestUbr', 'highestUbrFromReleaseInformation') -contains $pick) { $resultingUbr = $chosen.Ubr }
    # Champs facultatifs de l'entrée, lus sans erreur sous StrictMode.
    $fileNamePattern = $null
    if ($null -ne $Entry.PSObject.Properties['fileNamePattern']) { $fileNamePattern = $Entry.fileNamePattern }
    $prerequisites = @()
    if ($null -ne $Entry.PSObject.Properties['prerequisites']) { $prerequisites = @($Entry.prerequisites) }
    $runsAfter = @()
    if ($null -ne $Entry.PSObject.Properties['runsAfter']) { $runsAfter = @($Entry.runsAfter) }

    [pscustomobject]@{
        Category        = $Entry.category
        Pick            = $Entry.pick
        Kb              = $(if ($chosen) { $chosen.Kb } else { $null })
        UpdateId        = $(if ($representative) { $representative.UpdateId } else { $null })
        Title           = $(if ($representative) { $representative.Title } else { $null })
        Entries         = $(if ($chosen) { @($chosen.Members | ForEach-Object { $_.Item }) } else { @() })
        BaseBuilds      = $baseBuilds
        ResultingUbr    = $resultingUbr
        Version         = $(if ($chosen) { $chosen.Version } else { $null })
        Month           = $(if ($chosen) { $chosen.Month } else { $null })
        ReleaseDate     = $(if ($chosen) { $chosen.LastUpdated } else { $null })
        SizeBytes       = $(if ($representative) { $representative.SizeBytes } else { $null })
        FileNamePattern = $fileNamePattern
        Prerequisites   = $prerequisites
        RunsAfter       = $runsAfter
        Warnings        = $warnings.ToArray()
    }
}
