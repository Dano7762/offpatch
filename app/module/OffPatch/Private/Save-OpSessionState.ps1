function Save-OpSessionState {
    <#
    .SYNOPSIS
        Écrit state.json de façon atomique.

    .DESCRIPTION
        Cahier des charges 8.6 et 11 : fichier temporaire du même dossier (state.json.tmp), puis substitution en une
        seule opération (File.Replace s'il existe déjà, File.Move sinon), comme le manifeste. Une coupure pendant
        l'écriture laisse l'état précédent intact. UTF-8 sans marque.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject]$State,
        [string]$Path
    )

    if (-not $Path) { $Path = Get-OpPath -Name State }
    $json = ConvertTo-Json -InputObject $State -Depth 12
    if (-not $PSCmdlet.ShouldProcess($Path, 'Écriture atomique de l''état de session')) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $Path -Parent) -ErrorAction Stop | Out-Null
    $temp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        [System.IO.File]::Replace($temp, $Path, [NullString]::Value)
    } else {
        [System.IO.File]::Move($temp, $Path)
    }
}
