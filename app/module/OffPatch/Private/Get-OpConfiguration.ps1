function Get-OpConfiguration {
    <#
    .SYNOPSIS
        Charge et valide la configuration de l'outil (config/), ou lève une erreur qui liste toutes les anomalies.

    .DESCRIPTION
        Lit settings.json, catalog-queries.json, pinned-items.json et office/sources.json sous la racine de l'outil
        (Get-OpPath), puis les contrôle par Test-OpConfiguration. Une configuration incohérente arrête l'opération
        avant tout téléchargement ou toute installation, avec la liste complète des anomalies.
        Renvoie un objet Settings, CatalogQueries, PinnedItems, OfficeSources.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root
    )

    $config = Get-OpPath -Name Config -Root $Root
    $officeConfig = Get-OpPath -Name OfficeConfig -Root $Root
    $configuration = [pscustomobject]@{
        Settings       = Read-OpJsonFile -Path (Join-Path $config 'settings.json')
        CatalogQueries = Read-OpJsonFile -Path (Join-Path $config 'catalog-queries.json')
        PinnedItems    = Read-OpJsonFile -Path (Join-Path $config 'pinned-items.json')
        OfficeSources  = Read-OpJsonFile -Path (Join-Path $officeConfig 'sources.json')
    }
    $errors = @(Test-OpConfiguration -Configuration $configuration)
    if ($errors.Count -gt 0) {
        throw ("Configuration invalide ({0} anomalie(s)) :`n- {1}" -f $errors.Count, ($errors -join "`n- "))
    }
    $configuration
}
