function Test-OpItemFileHash {
    <#
    .SYNOPSIS
        Revérifie le SHA-256 des fichiers d'une étape par rapport au manifeste, juste avant de l'exécuter.

    .DESCRIPTION
        Cahier des charges 8.4 et 8.5 (R-10) : seuls les fichiers utilisés par l'étape sont relus. Chemins relatifs à
        depot/ (manifeste, 7.2). Renvoie la liste des écarts (fichier absent ou empreinte différente), vide si tout
        est conforme.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Depot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$File
    )

    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $File) {
        $path = Join-Path $Depot ([string]$entry.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("$($entry.path) : fichier absent du support."); continue }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) { $problems.Add("$($entry.path) : SHA-256 $hash au lieu de $($entry.sha256).") }
    }
    $problems.ToArray()
}
