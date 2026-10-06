function Read-OpManifest {
    <#
    .SYNOPSIS
        Lit et valide le manifeste du dépôt (depot/manifest.json).

    .DESCRIPTION
        Manifeste absent (dépôt neuf) : renvoie un manifeste vide, sans élément. Manifeste illisible ou incohérent
        (Test-OpManifest) : erreur qui donne le chemin et toutes les anomalies ; le dépôt n'est alors ni mis à jour ni
        utilisé pour une installation.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    if (-not $Path) { $Path = Get-OpPath -Name Manifest }
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return [pscustomobject]@{ schemaVersion = 1; generatedAt = $null; toolVersion = $null; items = @() }
    }
    $manifest = Read-OpJsonFile -Path $Path
    if ($null -eq $manifest.PSObject.Properties['items']) { $manifest | Add-Member -NotePropertyName items -NotePropertyValue @() }
    $errors = @(Test-OpManifest -Manifest $manifest)
    if ($errors.Count -gt 0) {
        throw ("Manifeste invalide ({0}, {1} anomalie(s)) :`n- {2}" -f $Path, $errors.Count, ($errors -join "`n- "))
    }
    $manifest
}
