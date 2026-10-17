function Save-OpReport {
    <#
    .SYNOPSIS
        Écrit le rapport d'intervention sur le support et en garde une copie dans ProgramData\OffPatch\logs.

    .DESCRIPTION
        Cahier des charges 8.8. Nom : rapports\AAAA-MM-JJ_NomPC_NumeroDeSerie.html (date du début de session ;
        caractères interdits dans un nom de fichier remplacés par « _ »). Écriture atomique (fichier temporaire puis
        renommage), UTF-8. Un échec de la copie dans ProgramData est journalisé sans annuler le rapport du support.
        Renvoie le chemin du rapport sur le support.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [pscustomobject]$Configuration,
        [string]$Root
    )

    function Get-SafeName([object]$Text) {
        $t = ([string]$Text).Trim()
        if (-not $t) { $t = 'inconnu' }
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $t = $t.Replace([string]$c, '_') }
        $t -replace '\s+', '_'
    }
    function Write-Atomic([string]$Path, [string]$Text) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Path $Path -Parent) -ErrorAction Stop | Out-Null
        $tmp = "$Path.tmp"
        [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding $true))
        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
    }

    function Get-Prop($Object, [string]$Name) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        $null
    }

    $start = Get-Prop $Session 'StartTime'
    if (-not $start) { $start = Get-Date }
    $before = Get-Prop $Session 'Before'
    $fileName = '{0}_{1}_{2}.html' -f ([datetime]$start).ToString('yyyy-MM-dd'), (Get-SafeName (Get-Prop $before 'ComputerName')), (Get-SafeName (Get-Prop $before 'SerialNumber'))
    $path = Join-Path (Get-OpPath -Name Reports -Root $Root) $fileName
    if (-not $PSCmdlet.ShouldProcess($path, 'Écriture du rapport d''intervention')) { return }

    $html = ConvertTo-OpReportHtml -Session $Session -Configuration $Configuration
    Write-Atomic $path $html
    Write-OpLog "Rapport d'intervention écrit : $path."
    try {
        Write-Atomic (Join-Path (Get-OpPath -Name ClientLogs) $fileName) $html
    } catch {
        Write-OpLog "Copie du rapport dans ProgramData non écrite : $($_.Exception.Message)" -Level WARN
    }
    $path
}
