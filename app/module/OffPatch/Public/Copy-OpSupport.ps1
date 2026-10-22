function Copy-OpSupport {
    <#
    .SYNOPSIS
        Copie OffPatch et le dépôt filtré sur un support (clé USB ou disque externe), puis y écrit le manifeste filtré.

    .DESCRIPTION
        Cahier des charges 7.4, étapes 4 à 6. Le plan est recalculé (Get-OpSupportPlan) : un refus arrête tout avant la
        moindre écriture. Puis, dans l'ordre :
          1. rapports du support rapatriés sur le poste (Copy-OpSupportReport) ;
          2. fichiers de la racine (Lancer-OffPatch.cmd, offpatch.root, README.md, LICENSE) copiés sans miroir ;
          3. app\, config\ et tools\ en miroir (robocopy /MIR) ;
          4. chaque dossier du dépôt retenu en miroir : depot\files\<empreinte> de chaque fichier, depot\office\<source>
             de chaque source Office ;
          5. manifeste filtré écrit de façon atomique dans depot\manifest.json du support, avec la date du dépôt
             d'origine (generatedAt) : seulement si toutes les copies ont réussi ;
          6. dossiers de depot\files et depot\office du support que le manifeste filtré ne connaît plus supprimés
             (anciennes cumulatives, cibles décochées), après l'écriture du manifeste.
        Le dossier rapports\ du support n'est jamais mis en miroir ni vidé. robocopy : codes 0 à 7 réussis, 8 et plus
        en erreur (copie arrêtée, manifeste non écrit). Annulation entre deux dossiers (jeton), jamais au milieu d'un
        fichier. Renvoie Destination, Reports, Folders (Path, ExitCode, Seconds), Removed, ManifestPath et Cancelled.

    .PARAMETER Destination
        Dossier de destination sur le support, en général la racine du lecteur (E:\).

    .PARAMETER Targets
        Cibles Windows à embarquer ; par défaut, celles cochées dans settings.json.

    .PARAMETER OfficeSources
        Sources Office à embarquer ; par défaut, celles actives dans sources.json.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER CancellationToken
        Jeton d'annulation (interface) : consulté avant chaque dossier.

    .EXAMPLE
        Copy-OpSupport -Destination F:\ -Targets win11-x64 -OfficeSources current -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [AllowEmptyCollection()][string[]]$Targets,
        [AllowEmptyCollection()][string[]]$OfficeSources,
        [string]$Root,
        [System.Threading.CancellationToken]$CancellationToken
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $selection = @{}
    if ($PSBoundParameters.ContainsKey('Targets')) { $selection.Targets = $Targets }
    if ($PSBoundParameters.ContainsKey('OfficeSources')) { $selection.OfficeSources = $OfficeSources }
    $plan = Get-OpSupportPlan -Destination $Destination -Root $Root @selection
    if (-not $plan.CanPrepare) { throw "Support non préparé : $($plan.Blocking -join ' ')" }
    $Destination = $plan.Destination
    if (-not $PSCmdlet.ShouldProcess($Destination, "Préparation du support ($(@($plan.Items).Count) élément(s) du dépôt)")) { return }
    $script:OpCancellation = $CancellationToken
    foreach ($w in $plan.Warnings) { Write-OpLog $w -Level WARN }
    Write-OpLog "Préparation du support $Destination : cibles $(@($plan.Targets) -join ', '), sources Office $(@($plan.OfficeSources) -join ', ')."

    $robocopy = Join-Path $env:SystemRoot 'System32\Robocopy.exe'
    $common = @('/R:2', '/W:5', '/NP', '/NFL', '/NDL', '/NJH', '/XJ')
    $folders = New-Object System.Collections.Generic.List[object]
    $cancelled = $false

    # Copie d'un dossier (ou de fichiers choisis de la racine) ; code 8 et plus : erreur, la préparation s'arrête.
    $copy = {
        param([string]$Relative, [string[]]$Arguments)
        $source = $Root
        $target = $Destination
        if ($Relative) { $source = Join-Path $Root $Relative; $target = [System.IO.Path]::Combine($Destination, $Relative) }
        $r = Invoke-OpProcess -FilePath $robocopy -ArgumentList (@($source, $target) + $Arguments + $common) -NoTimeout -Confirm:$false
        $name = $Relative
        if (-not $name) { $name = '(racine)' }
        $folders.Add([pscustomobject]@{ Path = $name; ExitCode = $r.ExitCode; Seconds = $r.Seconds })
        if ($r.ExitCode -ge 8) {
            $detail = (@(([string]$r.StdOut) -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 5) -join ' / '
            throw "Copie de $name vers le support en échec (robocopy, code $($r.ExitCode)) : $detail"
        }
        Write-OpLog "Copié sur le support : $name (robocopy $($r.ExitCode), $($r.Seconds) s)." -Level DEBUG
    }

    $reports = @(Copy-OpSupportReport -Destination $Destination -Root $Root -Confirm:$false)
    $depotFolders = New-Object System.Collections.Generic.List[string]
    foreach ($item in $plan.Items) {
        if ($item.PSObject.Properties['folder'] -and $item.folder) { $relative = 'depot\' + ([string]$item.folder -replace '/', '\') }
        else {
            foreach ($f in @($item.files | Where-Object { $_ })) {
                $relative = 'depot\' + (Split-Path -Parent ([string]$f.path -replace '/', '\'))
                if (-not $depotFolders.Contains($relative)) { $depotFolders.Add($relative) }
            }
            continue
        }
        if (-not $depotFolders.Contains($relative)) { $depotFolders.Add($relative) }
    }
    $steps = @(@{ Relative = ''; Arguments = @('Lancer-OffPatch.cmd', 'offpatch.root', 'README.md', 'LICENSE') }) +
        @('app', 'config', 'tools' | ForEach-Object { @{ Relative = $_; Arguments = @('/MIR') } }) +
        @($depotFolders | ForEach-Object { @{ Relative = $_; Arguments = @('/MIR') } })
    try {
        for ($i = 0; $i -lt $steps.Count; $i++) {
            Assert-OpNotCancelled
            $label = $steps[$i].Relative
            if (-not $label) { $label = 'fichiers de la racine' }
            Write-OpProgress ('Copie sur le support {0}/{1} : {2}' -f ($i + 1), $steps.Count, $label)
            & $copy $steps[$i].Relative $steps[$i].Arguments
        }
    } catch [System.OperationCanceledException] {
        $cancelled = $true
        Write-OpLog 'Préparation du support annulée : manifeste du support non mis à jour.' -Level WARN
    } finally {
        $script:OpCancellation = $null
    }
    if ($cancelled) {
        return [pscustomobject]@{ Destination = $Destination; Reports = $reports; Folders = $folders.ToArray(); Removed = @(); ManifestPath = $null; Cancelled = $true }
    }

    # Manifeste filtré, puis nettoyage de ce qu'il ne connaît plus.
    $source = Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root)
    $manifestPath = [System.IO.Path]::Combine($Destination, 'depot\manifest.json')
    Save-OpManifest -Manifest ([pscustomobject]@{ schemaVersion = 1; toolVersion = $source.toolVersion; items = @($plan.Items) }) -Path $manifestPath -GeneratedAt ([string]$source.generatedAt) -Confirm:$false
    Write-OpLog "Manifeste filtré écrit sur le support : $(@($plan.Items).Count) élément(s)."
    $removed = New-Object System.Collections.Generic.List[string]
    foreach ($parent in 'depot\files', 'depot\office') {
        $path = [System.IO.Path]::Combine($Destination, $parent)
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $path -Directory)) {
            $relative = "$parent\$($dir.Name)"
            if ($depotFolders.Contains($relative)) { continue }
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $removed.Add($relative)
            } catch {
                Write-OpLog "Dossier obsolète du support non supprimé ($relative) : $($_.Exception.Message)" -Level WARN
            }
        }
    }
    if ($removed.Count -gt 0) { Write-OpLog "Support : $($removed.Count) dossier(s) du dépôt qui ne sont plus retenus supprimés." }
    Write-OpLog "Support $Destination préparé : $($folders.Count) copie(s), $(@($reports | Where-Object { $_.Status -eq 'Copied' }).Count) rapport(s) rapatrié(s)."
    [pscustomobject]@{ Destination = $Destination; Reports = $reports; Folders = $folders.ToArray(); Removed = $removed.ToArray(); ManifestPath = $manifestPath; Cancelled = $false }
}
