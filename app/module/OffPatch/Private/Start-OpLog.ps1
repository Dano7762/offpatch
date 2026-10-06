function Start-OpLog {
    <#
    .SYNOPSIS
        Ouvre le journal d'une opération : face Dépôt ou session d'installation (cahier des charges, section 10).

    .DESCRIPTION
        Face Dépôt : <racine>\logs\depot_AAAA-MM-JJ_HHMMSS.log. Session d'installation :
        ProgramData\OffPatch\logs\session_AAAA-MM-JJ_HHMMSS.log, avec un sous-dossier du même nom pour les journaux
        de DISM et de l'ODT. Les dossiers sont créés si besoin. Le niveau minimal vient de settings.json
        (logging.level). Une file de messages (ConcurrentQueue) peut être fournie : chaque ligne écrite y est aussi
        déposée, pour l'interface (mise à jour par le Dispatcher, jamais depuis le thread de traitement).
        Renvoie un objet décrivant le journal (Path, ToolLogDirectory, Level, Queue).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Depot', 'Session')][string]$Kind,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue,
        [string]$Directory,
        [datetime]$Now = (Get-Date)
    )

    if (-not $Directory) {
        if ($Kind -eq 'Depot') { $Directory = Get-OpPath -Name Logs } else { $Directory = Get-OpPath -Name ClientLogs }
    }
    $prefix = 'depot'
    if ($Kind -eq 'Session') { $prefix = 'session' }
    $baseName = '{0}_{1:yyyy-MM-dd_HHmmss}' -f $prefix, $Now
    $path = Join-Path $Directory ($baseName + '.log')
    $toolLogs = Join-Path $Directory $baseName

    if ($PSCmdlet.ShouldProcess($path, 'Création du journal')) {
        New-Item -ItemType Directory -Force -Path $Directory -ErrorAction Stop | Out-Null
        if ($Kind -eq 'Session') { New-Item -ItemType Directory -Force -Path $toolLogs -ErrorAction Stop | Out-Null }
    }

    $script:OpLog = [pscustomobject]@{
        Path             = $path
        ToolLogDirectory = $(if ($Kind -eq 'Session') { $toolLogs } else { $null })
        Level            = $Level
        Queue            = $Queue
    }
    $script:OpLog
}
