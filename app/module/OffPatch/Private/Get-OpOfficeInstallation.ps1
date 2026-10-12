function Get-OpOfficeInstallation {
    <#
    .SYNOPSIS
        Relève l'Office Click-to-Run installé : produits, langues, canal, version ; $null sans Office Click-to-Run.

    .DESCRIPTION
        Lecture seule (cahier des charges 8.3, R-08). Registre HKLM\SOFTWARE\Microsoft\Office\ClickToRun :
          - Configuration : ProductReleaseIds (produits, séparés par des virgules), Platform, InstallationPath,
            VersionToReport (diagnostic seulement), CDNBaseUrl et UpdateChannel (canal : identifiant final de l'URL) ;
          - ProductReleaseIDs : clés de langue (xx-xx) sous la clé de chaque produit (<produit>.16), pour les produits
            de ProductReleaseIds.
        Canal retenu (ChannelId) : celui de UpdateChannel s'il est présent, sinon celui de CDNBaseUrl ; ChannelMismatch
        signale un désaccord entre les deux. Version installée : version de fichier de WINWORD.EXE, à défaut EXCEL.EXE,
        puis POWERPNT.EXE, dans <InstallationPath>\root\Office16 ; VersionFile donne le fichier lu.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $base = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun'
    $config = Get-ItemProperty -Path "$base\Configuration" -ErrorAction SilentlyContinue
    if (-not $config) { return $null }
    function Get-Value([string]$Name) {
        if ($null -ne $config.PSObject.Properties[$Name]) { return [string]$config.$Name }
        $null
    }
    function Get-ChannelId([string]$Url) {
        if ($Url -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?$') { return $Matches[1].ToLowerInvariant() }
        $null
    }

    $products = @((Get-Value 'ProductReleaseIds') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $languages = @(Get-ChildItem -Path "$base\ProductReleaseIDs" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^[a-z]{2,3}(-[a-z0-9]{2,4})+$' -and $products -contains ((Split-Path -Leaf $_.PSParentPath) -replace '\.\d+$', '') } |
            ForEach-Object { $_.PSChildName.ToLowerInvariant() } | Sort-Object -Unique)

    $cdn = Get-ChannelId (Get-Value 'CDNBaseUrl')
    $update = Get-ChannelId (Get-Value 'UpdateChannel')
    $channel = $update
    if (-not $channel) { $channel = $cdn }

    $installPath = Get-Value 'InstallationPath'
    $version = $null
    $versionFile = $null
    if ($installPath) {
        foreach ($exe in 'WINWORD.EXE', 'EXCEL.EXE', 'POWERPNT.EXE') {
            $path = Join-Path $installPath "root\Office16\$exe"
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $version = Get-OpFileVersion -Path $path
            if ($version) { $versionFile = $exe; break }
        }
    }

    [pscustomobject]@{
        Products         = $products
        Languages        = $languages
        Platform         = Get-Value 'Platform'
        ChannelId        = $channel
        CdnChannelId     = $cdn
        UpdateChannelId  = $update
        ChannelMismatch  = [bool]($cdn -and $update -and $cdn -ne $update)
        InstallationPath = $installPath
        Version          = $version
        VersionFile      = $versionFile
        VersionToReport  = Get-Value 'VersionToReport'
    }
}
