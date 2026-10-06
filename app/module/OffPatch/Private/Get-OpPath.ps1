function Get-OpPath {
    <#
    .SYNOPSIS
        Renvoie le chemin absolu d'un emplacement connu de l'outil (racine, dépôt, configuration, ProgramData).

    .DESCRIPTION
        Les emplacements du support sont calculés à partir de la racine (Get-OpRoot), jamais d'une lettre de
        lecteur en dur ; ceux du PC client à partir de la variable d'environnement ProgramData (cahier des
        charges, section 5). La fonction ne crée aucun dossier.
          Support : Root, Config, OfficeConfig, Depot, Manifest, DepotFiles, DepotOffice, DepotTemp, Tools, Odt,
                    Reports, Logs.
          PC client : ProgramData (ProgramData\OffPatch), State (state.json), ClientResume (resume.ps1),
                      ClientTemp, ClientLogs.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Root', 'Config', 'OfficeConfig', 'Depot', 'Manifest', 'DepotFiles', 'DepotOffice', 'DepotTemp', 'Tools', 'Odt',
            'Reports', 'Logs', 'ProgramData', 'State', 'ClientResume', 'ClientTemp', 'ClientLogs')]
        [string]$Name,
        [string]$Root
    )

    $relative = @{
        Root         = '.'
        Config       = 'config'
        OfficeConfig = 'config\office'
        Depot        = 'depot'
        Manifest     = 'depot\manifest.json'
        DepotFiles   = 'depot\files'
        DepotOffice  = 'depot\office'
        DepotTemp    = 'depot\.tmp'
        Tools        = 'tools'
        Odt          = 'tools\odt'
        Reports      = 'rapports'
        Logs         = 'logs'
    }
    $client = @{
        ProgramData  = '.'
        State        = 'state.json'
        ClientResume = 'resume.ps1'
        ClientTemp   = 'temp'
        ClientLogs   = 'logs'
    }

    if ($relative.ContainsKey($Name)) {
        if (-not $Root) { $Root = Get-OpRoot }
        if ($Name -eq 'Root') { return $Root }
        return (Join-Path $Root $relative[$Name])
    }

    if (-not $env:ProgramData) { throw 'Variable d''environnement ProgramData absente : emplacements du PC client inconnus.' }
    $base = Join-Path $env:ProgramData 'OffPatch'
    if ($Name -eq 'ProgramData') { return $base }
    Join-Path $base $client[$Name]
}
