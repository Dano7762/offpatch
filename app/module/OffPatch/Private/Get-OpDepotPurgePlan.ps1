function Get-OpDepotPurgePlan {
    <#
    .SYNOPSIS
        Détermine les éléments du manifeste à retirer selon la rétention, et les fichiers devenus inutiles.

    .DESCRIPTION
        Fonction pure (cahier des charges 7.3). Règles :
          - cumulatives Windows (windows-lcu) et .NET (dotnet) : par cible et par catégorie, on garde les
            retention.windowsMonths.<cible> plus récentes (date de publication, puis UBR, puis numéro de KB) ;
          - définitions et plateforme Defender : par cible, seulement la version la plus élevée ;
          - éléments épinglés (pinned-items.json) : jamais retirés ;
          - autres catégories (checkpoint, sources Office, traitées ailleurs) et cibles absentes de
            retention.windowsMonths : gardées.
        Un fichier n'est à supprimer que si plus aucun élément gardé ne le référence (comptage de références,
        section 5). Renvoie Kept et Removed (éléments du manifeste) et RemovedFiles (chemins relatifs à depot/,
        avec leur taille).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [Parameter(Mandatory)][pscustomobject]$Configuration
    )

    $pinnedIds = @($Configuration.PinnedItems.items | ForEach-Object { $_.id })
    $months = $Configuration.Settings.retention.windowsMonths
    $items = @($Manifest.items | Where-Object { $null -ne $_ })
    $removedIds = @{}

    function Get-Text($Object, [string]$Name) {
        if ($null -ne $Object.PSObject.Properties[$Name]) { return [string]$Object.$Name }
        ''
    }
    foreach ($group in @($items | Where-Object { $pinnedIds -notcontains $_.id } | Group-Object -Property { '{0}-{1}|{2}' -f $_.target.os, $_.target.arch, $_.category })) {
        $first = $group.Group[0]
        $target = '{0}-{1}' -f $first.target.os, $first.target.arch
        $keep = $null
        if (@('windows-lcu', 'dotnet') -contains $first.category) {
            if ($null -eq $months.PSObject.Properties[$target]) { continue }
            $keep = [int]$months.$target
            $sorted = @($group.Group | Sort-Object -Descending -Property `
                @{ Expression = { Get-Text $_ 'releaseDate' } },
                @{ Expression = { if ($null -ne $_.PSObject.Properties['resultingUbr']) { [int]$_.resultingUbr } else { -1 } } },
                @{ Expression = { [int64](((Get-Text $_ 'kb') -replace '\D', '') + '0') } })
        } elseif (@('defender', 'defender-platform') -contains $first.category) {
            $keep = 1
            $sorted = @($group.Group | Sort-Object -Descending -Property @{ Expression = { $v = $null; if ([version]::TryParse((Get-Text $_ 'version'), [ref]$v)) { $v } else { [version]'0.0' } } })
        } else {
            continue
        }
        foreach ($old in @($sorted | Select-Object -Skip $keep)) { $removedIds[$old.id] = $true }
    }

    $kept = @($items | Where-Object { -not $removedIds.ContainsKey($_.id) })
    $removed = @($items | Where-Object { $removedIds.ContainsKey($_.id) })
    $referenced = @{}
    foreach ($k in $kept) { foreach ($f in @($k.files)) { if ($f) { $referenced[[string]$f.path] = $true } } }
    $files = @{}
    foreach ($r in $removed) {
        foreach ($f in @($r.files)) {
            if ($f -and -not $referenced.ContainsKey([string]$f.path)) { $files[[string]$f.path] = [pscustomobject]@{ Path = [string]$f.path; Size = [long]$f.size } }
        }
    }
    [pscustomobject]@{
        Kept         = $kept
        Removed      = $removed
        RemovedFiles = @($files.Values | Sort-Object -Property Path)
    }
}
