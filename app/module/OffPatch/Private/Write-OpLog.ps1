function Write-OpLog {
    <#
    .SYNOPSIS
        Écrit une ligne dans le journal ouvert par Start-OpLog.

    .DESCRIPTION
        Format (cahier des charges, section 10) : « 2026-10-14 09:12:03 [INFO] message ». Les lignes sous le niveau
        minimal du journal sont ignorées. Toute suite de cinq groupes de cinq caractères (forme d'une clé de produit)
        est masquée avant l'écriture : une clé n'est jamais écrite dans un journal (CLAUDE.md). La ligne est aussi
        déposée dans la file de messages de l'interface, si elle existe. Le journal ne doit jamais interrompre
        l'outil : sans journal ouvert, la ligne part dans le flux Verbose ; un fichier verrouillé est retenté trois
        fois, puis la ligne part dans le flux Warning.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [datetime]$Now = (Get-Date)
    )

    $order = @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3 }
    $safe = [regex]::Replace($Message, '\b[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}\b', 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f $Now, $Level, $safe

    $log = $null
    if (Get-Variable -Name OpLog -Scope Script -ErrorAction SilentlyContinue) { $log = $script:OpLog }
    if (-not $log) {
        Write-Verbose $line
        return
    }
    if ($order[$Level] -lt $order[$log.Level]) { return }

    $written = $false
    for ($attempt = 1; $attempt -le 3 -and -not $written; $attempt++) {
        try {
            [System.IO.File]::AppendAllText($log.Path, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
            $written = $true
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
    if (-not $written) { Write-Warning "Journal inaccessible ($($log.Path)) : $line" }
    if ($log.Queue) {
        $log.Queue.Enqueue([pscustomobject]@{ Time = $Now; Level = $Level; Message = $safe; Line = $line })
    }
}
