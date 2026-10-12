function ConvertTo-OpOfficeManifestItem {
    <#
    .SYNOPSIS
        Construit l'élément office-source du manifeste (cahier des charges 7.2) pour la version d'une source Office
        relevée par Save-OpOfficeSource.

    .DESCRIPTION
        Identifiant office-<source>-<version> ; canal, version, langues et dossier de la source (chemin relatif à
        depot/). Les fichiers sont ceux de la source, avec leur SHA-256 (7.1, 10), hormis les autres versions encore
        présentes (dossier Office\Data\<version>\ et v64_<version>.cab), que la purge retire ensuite (7.3, R-07).
        Ordre 50 : Office est la dernière étape du plan (8.3).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Result,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Depot
    )

    $version = [string]$Result.Version
    $source = (Join-Path $Depot ($Folder -replace '/', '\')).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -Force -ErrorAction Stop | Sort-Object -Property FullName | ForEach-Object {
            $relative = $_.FullName.Substring($source.Length + 1)
            if ($relative -match '^Office\\Data\\(v64_)?(\d+\.\d+\.\d+\.\d+)' -and $Matches[2] -ne $version) { return }
            [pscustomobject][ordered]@{
                path   = "$Folder/$($relative -replace '\\', '/')"
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                size   = [long]$_.Length
            }
        })

    [pscustomobject][ordered]@{
        id             = "office-$($Result.Id)-$version"
        category       = 'office-source'
        channel        = $Result.Channel
        version        = $version
        languages      = @($Result.Languages)
        folder         = $Folder
        order          = 50
        requiresReboot = $false
        prerequisites  = @()
        runsAfter      = @()
        files          = $files
    }
}
