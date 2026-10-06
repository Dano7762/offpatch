function Save-OpManifest {
    <#
    .SYNOPSIS
        Écrit le manifeste du dépôt de façon atomique, après l'avoir validé.

    .DESCRIPTION
        Le manifeste est d'abord contrôlé (Test-OpManifest) : un manifeste incohérent n'est jamais écrit. Il est
        ensuite écrit dans un fichier temporaire du même dossier (manifest.json.tmp), puis substitué au manifeste en
        une seule opération (File.Replace s'il existe déjà, File.Move sinon) : une coupure pendant l'écriture laisse
        l'ancien manifeste intact (CLAUDE.md, cahier des charges 7.1). generatedAt est mis à l'heure UTC courante.
        UTF-8 sans marque.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject]$Manifest,
        [string]$Path,
        [string]$ToolVersion
    )

    if (-not $Path) { $Path = Get-OpPath -Name Manifest }
    $errors = @(Test-OpManifest -Manifest $Manifest)
    if ($errors.Count -gt 0) {
        throw ("Manifeste non écrit, {0} anomalie(s) :`n- {1}" -f $errors.Count, ($errors -join "`n- "))
    }

    $document = [ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        toolVersion   = $(if ($ToolVersion) { $ToolVersion } else { $Manifest.toolVersion })
        items         = @($Manifest.items | Where-Object { $null -ne $_ })
    }
    $json = ConvertTo-Json -InputObject $document -Depth 12
    if (-not $PSCmdlet.ShouldProcess($Path, 'Écriture atomique du manifeste')) { return }

    $folder = Split-Path -Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $folder -ErrorAction Stop | Out-Null
    $temp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -Path $Path -PathType Leaf) {
        [System.IO.File]::Replace($temp, $Path, [NullString]::Value)
    } else {
        [System.IO.File]::Move($temp, $Path)
    }
}
