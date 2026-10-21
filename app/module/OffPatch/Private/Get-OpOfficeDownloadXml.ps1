function Get-OpOfficeDownloadXml {
    <#
    .SYNOPSIS
        Génère le XML de téléchargement de l'ODT (setup.exe /download) de chaque source Office.

    .DESCRIPTION
        Fonction sans effet de bord (cahier des charges 6.3, 7.1). Remplit config\office\download.xml.template pour
        chaque source active de office\sources.json (enabled absent ou vrai) : chemin absolu du dossier de la source dans le dépôt, canal, produit
        de téléchargement (downloadProductId) et une ligne Language par langue de la source. Une source d'un canal
        et d'une langue n'est pas propre à un produit (R-08) : le produit ne sert qu'à demander le téléchargement.
        Les valeurs sont échappées pour XML et le résultat est relu comme XML avant d'être renvoyé.
        Renvoie un objet par source : Id, Channel, Languages, SourcePath, Xml.

    .EXAMPLE
        Get-OpOfficeDownloadXml -Configuration (Get-OpConfiguration) | Select-Object Id, SourcePath
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [string]$Root
    )

    $templatePath = Join-Path (Get-OpPath -Name OfficeConfig -Root $Root) 'download.xml.template'
    $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 -ErrorAction Stop
    $depot = Get-OpPath -Name Depot -Root $Root
    foreach ($src in @($Configuration.OfficeSources.sources)) {
        # Source décochée dans l'onglet Dépôt (enabled false) : pas téléchargée.
        if ($src.PSObject.Properties['enabled'] -and $src.enabled -eq $false) { continue }
        $sourcePath = Join-Path $depot ([string]$src.folder -replace '/', '\')
        $languages = @($src.languages | ForEach-Object { '      <Language ID="{0}" />' -f [Security.SecurityElement]::Escape([string]$_) })
        $xml = $template.Replace('{{SourcePath}}', [Security.SecurityElement]::Escape($sourcePath))
        $xml = $xml.Replace('{{Channel}}', [Security.SecurityElement]::Escape([string]$src.channel))
        $xml = $xml.Replace('{{ProductId}}', [Security.SecurityElement]::Escape([string]$src.downloadProductId))
        $xml = $xml.Replace('{{LanguageElements}}', ($languages -join "`r`n"))
        try { [void][xml]$xml }
        catch { throw "XML de téléchargement de la source $($src.id) invalide (modèle $templatePath) : $($_.Exception.Message)" }
        [pscustomobject]@{
            Id         = [string]$src.id
            Channel    = [string]$src.channel
            Languages  = @($src.languages)
            SourcePath = $sourcePath
            Xml        = $xml
        }
    }
}
