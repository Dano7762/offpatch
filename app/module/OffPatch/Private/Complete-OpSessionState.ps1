function Complete-OpSessionState {
    <#
    .SYNOPSIS
        Clôt la session : archive state.json dans les journaux de ProgramData.

    .DESCRIPTION
        Cahier des charges 8.6 (fin de session). state.json est déplacé dans ProgramData\OffPatch\logs sous le nom
        state_AAAA-MM-JJ_HHMMSS_<sessionId>.json (date de début de session), puis le fichier temporaire éventuel est
        supprimé. Sans session en cours, rien n'est fait. Renvoie le chemin de l'archive, ou $null.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [string]$Path,
        [string]$LogDirectory
    )

    if (-not $Path) { $Path = Get-OpPath -Name State }
    if (-not $LogDirectory) { $LogDirectory = Get-OpPath -Name ClientLogs }
    $state = Read-OpSessionState -Path $Path
    if (-not $state) { return $null }
    $start = Get-Date
    if ($state.PSObject.Properties['startTime'] -and $state.startTime) { $start = [datetime]$state.startTime }
    $archive = Join-Path $LogDirectory ('state_{0:yyyy-MM-dd_HHmmss}_{1}.json' -f $start, $state.sessionId)
    if (-not $PSCmdlet.ShouldProcess($Path, "Archivage de l'état de session vers $archive")) { return }
    New-Item -ItemType Directory -Force -Path $LogDirectory -ErrorAction Stop | Out-Null
    Move-Item -LiteralPath $Path -Destination $archive -Force -ErrorAction Stop
    Remove-Item -LiteralPath ($Path + '.tmp') -Force -ErrorAction SilentlyContinue
    Write-OpLog "Session $($state.sessionId) close : état archivé dans $archive."
    $archive
}
