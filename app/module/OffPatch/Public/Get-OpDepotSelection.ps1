function Get-OpDepotSelection {
    <#
    .SYNOPSIS
        Lit, sans rien modifier, les cibles et les sources Office du dépôt, cochées ou non (onglet Dépôt).

    .DESCRIPTION
        Cahier des charges 6.1, 6.3 et 9. AvailableTargets : cibles qui ont des recherches dans
        catalog-queries.json ; Targets : cibles cochées (settings.json) ; OfficeSources : une entrée par source de
        config\office\sources.json (Id, Channel, Enabled — enabled absent vaut true —, Languages).
        Modification : Set-OpDepotSelection.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Get-OpDepotSelection | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    [pscustomobject]@{
        AvailableTargets = @($configuration.CatalogQueries.targets.PSObject.Properties | ForEach-Object { $_.Name })
        Targets          = @($configuration.Settings.targets)
        OfficeSources    = @($configuration.OfficeSources.sources | ForEach-Object {
                [pscustomobject]@{
                    Id = [string]$_.id; Channel = [string]$_.channel; Languages = @($_.languages)
                    Enabled = -not ($_.PSObject.Properties['enabled'] -and $_.enabled -eq $false)
                }
            })
    }
}
