function Read-OpMsuPackage {
    <#
    .SYNOPSIS
        Lit dans un .msu le nom et la version du paquet (update.mum du .cab principal).

    .DESCRIPTION
        Étape 6 de la mise à jour du dépôt (cahier des charges 7.1, 7.2 ; R-05, R-09). Les .cab du .msu sont extraits
        avec expand.exe dans un dossier de travail (WorkFolder, supprimé ensuite), puis update.mum de chaque .cab ;
        le premier assemblyIdentity lu donne le paquet. Sont ignorés : wsusscan.cab et le SSU embarqué dans une
        cumulative Windows 10 (SSU-*.cab). Le .msu d'une cumulative Windows 11 24H2 ou plus récente n'est pas lisible
        par expand.exe (R-09) : la fonction renvoie alors $null, sans erreur.
        Renvoie un objet name, version, ou $null.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorkFolder,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 1800
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Extraction de update.mum')) { return }
    $expand = Join-Path $env:SystemRoot 'System32\expand.exe'
    New-Item -ItemType Directory -Force -Path $WorkFolder -ErrorAction Stop | Out-Null
    try {
        $r = Invoke-OpProcess -FilePath $expand -ArgumentList '-F:*.cab', $Path, $WorkFolder -TimeoutSeconds $TimeoutSeconds -Confirm:$false
        if ($r.TimedOut -or $r.ExitCode -ne 0) { throw "expand.exe n'a pas pu ouvrir $([System.IO.Path]::GetFileName($Path)) (code $($r.ExitCode))." }
        foreach ($cab in @(Get-ChildItem -LiteralPath $WorkFolder -Filter '*.cab' -File)) {
            if ($cab.Name -match '(?i)^(wsusscan|ssu-)') { continue }
            $mumFolder = Join-Path $WorkFolder ($cab.BaseName + '-mum')
            New-Item -ItemType Directory -Force -Path $mumFolder | Out-Null
            $null = Invoke-OpProcess -FilePath $expand -ArgumentList '-F:update.mum', $cab.FullName, $mumFolder -TimeoutSeconds $TimeoutSeconds -Confirm:$false
            $mum = Join-Path $mumFolder 'update.mum'
            if (-not (Test-Path -LiteralPath $mum -PathType Leaf)) { continue }
            [xml]$xml = [System.IO.File]::ReadAllText($mum)
            $identity = $xml.assembly.assemblyIdentity
            if ($identity -and $identity.name -and $identity.version) {
                return [pscustomobject]@{ name = [string]$identity.name; version = [string]$identity.version }
            }
        }
        $null
    } finally {
        Remove-Item -LiteralPath $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
