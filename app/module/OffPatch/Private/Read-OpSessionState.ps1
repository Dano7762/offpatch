function Read-OpSessionState {
    <#
    .SYNOPSIS
        Lit state.json de la session en cours ; $null s'il n'y a pas de session.

    .DESCRIPTION
        Cahier des charges 8.6. Un fichier illisible ou d'un autre schéma est une erreur explicite : la session ne
        repart jamais sur un état qu'elle ne comprend pas. Un fichier temporaire laissé par une écriture interrompue
        (state.json.tmp) est ignoré : seul le dernier état complet fait foi (Save-OpSessionState).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    if (-not $Path) { $Path = Get-OpPath -Name State }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "État de session illisible ($Path) : $($_.Exception.Message)"
    }
    if (-not $state -or -not $state.PSObject.Properties['schemaVersion'] -or [int]$state.schemaVersion -ne 1 -or -not $state.PSObject.Properties['sessionId']) {
        throw "État de session non reconnu ($Path) : schemaVersion 1 et sessionId attendus."
    }
    $state
}
