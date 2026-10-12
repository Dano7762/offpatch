function Get-OpOfficeSourceVersion {
    <#
    .SYNOPSIS
        Lit la version d'une source Office du dépôt, celle que désigne son index v64.cab.

    .DESCRIPTION
        Cahier des charges 7.1, 7.3 ; structure mesurée en R-07 : setup.exe /download écrit <source>\Office\Data\
        avec un dossier par version, un v64_<version>.cab par version et v64.cab, qui désigne la dernière. v64.cab
        contient v64.hash, dont la deuxième ligne est le numéro de version ; il est extrait avec expand.exe dans un
        dossier de travail (WorkFolder, supprimé ensuite). La version lue doit avoir son dossier dans Office\Data.
        Sans v64.cab (téléchargement fait avec l'attribut Version, R-07), la version la plus élevée parmi les
        dossiers est renvoyée, avec FromIndex à faux. Renvoie Version ([version]), FromIndex et Versions (toutes
        les versions présentes), ou $null quand la source ne contient aucune version.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorkFolder
    )

    $data = Join-Path $Path 'Office\Data'
    $versions = @()
    if (Test-Path -LiteralPath $data -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $data -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { [version]$_.Name } | Sort-Object)
    }
    if ($versions.Count -eq 0) { return $null }

    $index = Join-Path $data 'v64.cab'
    if (-not (Test-Path -LiteralPath $index -PathType Leaf)) {
        return [pscustomobject]@{ Version = $versions[-1]; FromIndex = $false; Versions = $versions }
    }
    $expand = Join-Path $env:SystemRoot 'System32\expand.exe'
    New-Item -ItemType Directory -Force -Path $WorkFolder -ErrorAction Stop | Out-Null
    try {
        $r = Invoke-OpProcess -FilePath $expand -ArgumentList '-F:v64.hash', $index, $WorkFolder -TimeoutSeconds 300 -Confirm:$false
        $hash = Join-Path $WorkFolder 'v64.hash'
        if ($r.TimedOut -or $r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $hash -PathType Leaf)) {
            throw "Index de la source Office illisible : v64.hash absent de $index (expand.exe, code $($r.ExitCode))."
        }
        $lines = @(Get-Content -LiteralPath $hash -Encoding UTF8 -ErrorAction Stop)
        $text = ''
        if ($lines.Count -ge 2) { $text = ([string]$lines[1]).Trim() }
        if ($text -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "Index de la source Office non reconnu : deuxième ligne de v64.hash « $text » ($index)." }
        $version = [version]$text
        if ($versions -notcontains $version) { throw "Index de la source Office incohérent : v64.cab désigne $version, dossier absent de $data." }
        [pscustomobject]@{ Version = $version; FromIndex = $true; Versions = $versions }
    } finally {
        Remove-Item -LiteralPath $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
