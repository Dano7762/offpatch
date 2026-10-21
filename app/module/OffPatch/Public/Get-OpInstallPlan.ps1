function Get-OpInstallPlan {
    <#
    .SYNOPSIS
        Construit, en lecture seule, le plan d'installation de ce PC : étapes ordonnées, prérequis, redémarrages.

    .DESCRIPTION
        Cahier des charges 8.3. Part des états de Get-OpUpdateState (une ligne par élément) et des champs du
        manifeste (order, requiresReboot, prerequisites, runsAfter, resultingUbr, minUbr).
          - Ordre : order croissant, puis chaque étape après ses dépendances (prerequisites et runsAfter). Une valeur
            de dépendance est un identifiant d'élément ou un code de catégorie (tous les éléments de cette catégorie).
          - Prérequis bloquants, évalués dans l'ordre du plan : un prérequis à jour ou non applicable est rempli, un
            prérequis à installer plus tôt dans le plan aussi ; ignoré, absent du dépôt ou en erreur, il ne l'est
            pas, et l'étape passe à SkippedPrerequisite avec son motif. Les étapes qui en dépendent par un prérequis
            sont ignorées à leur tour ; celles qui n'en dépendent que par l'ordre restent prévues.
          - minUbr (enablement package) : comparé à l'UBR projeté, c'est-à-dire l'UBR courant relevé par les
            checkpoints et cumulatives prévues plus tôt (resultingUbr). Jamais d'étape lancée sous minUbr (R-03).
          - Redémarrage (RebootAfter) : après une étape à installer qui le demande (requiresReboot), sauf si l'étape
            à installer suivante est du même lot ; checkpoints et cumulative forment un seul lot, avec un seul
            redémarrage (R-02). Le .NET qui renvoie 3010 est traité par l'exécuteur.
        Seules les étapes à l'état Pending sont à exécuter ; les autres lignes restent dans le plan pour le rapport.
        L'état réel est revérifié avant chaque étape par l'exécuteur, pas ici.
        Renvoie Sequence, Id, Category, CategoryLabel, State, StateLabel (libellés français), Reason, Installed, Available, RequiresReboot, RebootAfter,
        Prerequisites et RunsAfter (identifiants résolus).

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER SystemInfo
        Relevé de Get-OpSystemInfo déjà fait ; relu sinon.

    .PARAMETER UpdateState
        États de Get-OpUpdateState déjà calculés ; recalculés sinon.

    .PARAMETER ExcludeId
        Étapes qui ne seront plus tentées (abandonnées ou annulées dans la session) : même encore à installer, elles
        ne remplissent aucun prérequis et ne font pas monter l'UBR projeté. Sans cela, un enablement package serait
        lancé après une cumulative abandonnée, et annulé par Windows au redémarrage.

    .EXAMPLE
        Get-OpInstallPlan | Format-Table Sequence, Category, Id, State, RebootAfter, Reason -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [pscustomobject]$SystemInfo,
        [object[]]$UpdateState,
        [string[]]$ExcludeId = @()
    )

    if (-not $Root) { $Root = Get-OpRoot }
    if (-not $SystemInfo) { $SystemInfo = Get-OpSystemInfo -Root $Root }
    if (-not $UpdateState) { $UpdateState = @(Get-OpUpdateState -Root $Root -SystemInfo $SystemInfo) }
    $manifest = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)
    $categories = 'windows-lcu', 'windows-checkpoint', 'windows-ekb', 'windows-ssu', 'dotnet', 'defender-platform', 'defender', 'office-source'
    # Lot de redémarrage : checkpoints et cumulative s'enchaînent avant un seul redémarrage (R-02, R-03).
    $batch = @{ 'windows-ssu' = 'servicing'; 'windows-checkpoint' = 'servicing'; 'windows-lcu' = 'servicing' }

    function Get-Prop($Object, [string]$Name) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        $null
    }

    $steps = @(for ($i = 0; $i -lt @($UpdateState).Count; $i++) {
            $s = @($UpdateState)[$i]
            $item = $null
            if ($s.Id) { $item = @($manifest.items | Where-Object { $_ -and $_.id -eq $s.Id }) | Select-Object -First 1 }
            $order = Get-Prop $item 'order'
            if ($null -eq $order) { $order = [int]::MaxValue }
            [pscustomobject]@{
                Index = $i; Order = [int]$order; Item = $item
                Id = $s.Id; Category = $s.Category; State = $s.State; Reason = $s.Reason; Installed = $s.Installed; Available = $s.Available
                RequiresReboot = [bool](Get-Prop $item 'requiresReboot'); RebootAfter = $false
                PrerequisiteValues = @(Get-Prop $item 'prerequisites' | Where-Object { $_ })
                RunsAfterValues = @(Get-Prop $item 'runsAfter' | Where-Object { $_ })
                Prerequisites = @(); RunsAfter = @(); Unresolved = @()
            }
        })

    # Résolution des dépendances : identifiant d'élément, sinon code de catégorie. Un identifiant inconnu est un
    # prérequis absent du dépôt ; une catégorie sans élément n'a rien d'applicable, donc rien à attendre.
    foreach ($step in $steps) {
        foreach ($kind in 'Prerequisites', 'RunsAfter') {
            $ids = New-Object System.Collections.Generic.List[string]
            $values = $step.RunsAfterValues
            if ($kind -eq 'Prerequisites') { $values = $step.PrerequisiteValues }
            foreach ($value in $values) {
                $found = @($steps | Where-Object { $_.Id -and $_ -ne $step -and ($_.Id -eq $value -or ($_.Category -eq $value -and $_.Category -ne $step.Category)) })
                if ($found.Count -gt 0) { foreach ($f in $found) { if (-not $ids.Contains($f.Id)) { $ids.Add($f.Id) } } }
                elseif ($kind -eq 'Prerequisites' -and $categories -notcontains $value) { $step.Unresolved += $value }
            }
            $step.$kind = $ids.ToArray()
        }
    }

    # Tri : à chaque tour, la première étape (order, puis rang de détection) dont toutes les dépendances sont placées.
    # ponytail: O(n²), une vingtaine d'étapes au plus.
    $remaining = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($steps | Sort-Object Order, Index)) { $remaining.Add($s) }
    $placed = New-Object System.Collections.Generic.List[object]
    $placedIds = @{}
    while ($remaining.Count -gt 0) {
        $next = $null
        foreach ($s in $remaining) {
            if (@(@($s.Prerequisites) + @($s.RunsAfter) | Where-Object { -not $placedIds.ContainsKey($_) }).Count -eq 0) { $next = $s; break }
        }
        if (-not $next) {
            $next = $remaining[0]
            Write-OpLog -Level WARN -Message "Plan : dépendances circulaires autour de $($next.Id) ; ordre du manifeste conservé."
        }
        [void]$remaining.Remove($next)
        $placed.Add($next)
        if ($next.Id) { $placedIds[$next.Id] = $true }
    }

    # Prérequis bloquants et UBR projeté, dans l'ordre du plan.
    $projectedUbr = [int]$SystemInfo.Ubr
    $done = @{}
    foreach ($step in $placed) {
        if ($step.State -eq 'Pending') {
            $why = $null
            if ($step.Unresolved.Count -gt 0) { $why = "prérequis $($step.Unresolved[0]) absent du dépôt" }
            foreach ($id in $step.Prerequisites) {
                if ($why) { break }
                $p = @($placed | Where-Object { $_.Id -eq $id })[0]
                $met = @('UpToDate', 'NotApplicable') -contains $p.State -or ($p.State -eq 'Pending' -and $done.ContainsKey($id))
                if (-not $met) { $why = "prérequis $id : $($p.State)" }
            }
            $minUbr = Get-Prop $step.Item 'minUbr'
            if (-not $why -and $null -ne $minUbr -and $projectedUbr -lt [int]$minUbr) { $why = "UBR $projectedUbr (projeté après les étapes précédentes) inférieur à $minUbr" }
            if ($why) {
                $step.State = 'SkippedPrerequisite'
                $step.Reason = "Ignorée : $why."
            }
            elseif (@('windows-checkpoint', 'windows-lcu') -contains $step.Category -and $ExcludeId -notcontains $step.Id) {
                $resulting = Get-Prop $step.Item 'resultingUbr'
                if ($null -ne $resulting -and [int]$resulting -gt $projectedUbr) { $projectedUbr = [int]$resulting }
            }
        }
        if ($step.Id -and $ExcludeId -notcontains $step.Id) { $done[$step.Id] = $true }
    }

    # Points de redémarrage.
    $pending = @($placed | Where-Object { $_.State -eq 'Pending' })
    for ($i = 0; $i -lt $pending.Count; $i++) {
        if (-not $pending[$i].RequiresReboot) { continue }
        $group = $batch[$pending[$i].Category]
        $following = $null
        if ($i + 1 -lt $pending.Count) { $following = $pending[$i + 1] }
        $pending[$i].RebootAfter = -not ($group -and $following -and $batch[$following.Category] -eq $group)
    }

    $sequence = 0
    foreach ($step in $placed) {
        $sequence++
        [pscustomobject]@{
            Sequence = $sequence; Id = $step.Id; Category = $step.Category; CategoryLabel = ConvertTo-OpCategoryLabel $step.Category; State = $step.State; StateLabel = ConvertTo-OpStateLabel $step.State; Reason = $step.Reason
            Installed = $step.Installed; Available = $step.Available; RequiresReboot = $step.RequiresReboot; RebootAfter = $step.RebootAfter
            Prerequisites = $step.Prerequisites; RunsAfter = $step.RunsAfter
        }
    }
}
