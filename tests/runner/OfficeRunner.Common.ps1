# Fonctions communes aux essais Office sur runners GitHub (R-07, R-08). Chargé par dot-sourcing.
# Réservé aux runners hébergés : certaines fonctions modifient le système (fichier hosts, registre Click-to-Run).

function Initialize-OdtTool {
    <#
    .SYNOPSIS
        Récupère la dernière version de l'ODT par la page officielle du Centre de téléchargement et l'extrait.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkDirectory,
        [string]$DownloadPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'
    )
    $odtFolder = Join-Path $WorkDirectory 'odt'
    New-Item -ItemType Directory -Force -Path $odtFolder | Out-Null
    $page = (Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing -ErrorAction Stop).Content
    $odtUrl = [regex]::Matches($page, 'https://download\.microsoft\.com/[^"\\ ]+officedeploymenttool[^"\\ ]+\.exe') | ForEach-Object { $_.Value } | Select-Object -First 1
    if (-not $odtUrl) { throw 'Lien officedeploymenttool_*.exe introuvable' }
    $odtExe = Join-Path $WorkDirectory ([uri]$odtUrl).Segments[-1]
    & curl.exe --fail --silent --show-error --location --retry 3 --output $odtExe $odtUrl
    if ($LASTEXITCODE -ne 0) { throw "curl a échoué ($LASTEXITCODE) pour l'ODT" }
    Start-Process -FilePath $odtExe -ArgumentList '/quiet', "/extract:$odtFolder" -Wait | Out-Null
    Join-Path $odtFolder 'setup.exe'
}

function Invoke-OdtSetup {
    <#
    .SYNOPSIS
        Lance setup.exe /download ou /configure avec un XML donné et renvoie le code retour et la durée.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Setup,
        [Parameter(Mandatory)][ValidateSet('download', 'configure')][string]$Mode,
        [Parameter(Mandatory)][string]$Xml,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    Set-Content -Path $ConfigPath -Value $Xml -Encoding UTF8
    $started = Get-Date
    $process = Start-Process -FilePath $Setup -ArgumentList "/$Mode", $ConfigPath -Wait -PassThru -WorkingDirectory (Split-Path -Parent $Setup)
    [pscustomobject]@{ ExitCode = $process.ExitCode; Seconds = [math]::Round(((Get-Date) - $started).TotalSeconds) }
}

function Get-ClickToRunState {
    <#
    .SYNOPSIS
        Relève, en lecture seule, l'état de l'Office Click-to-Run installé.
    #>
    [CmdletBinding()]
    param()
    $key = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $c2r = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    $root = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16'
    $cultures = @()
    if (Test-Path $root) {
        $cultures = @(Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -match '^\d{4}$' } | ForEach-Object { $_.Name })
    }
    if (-not $c2r) {
        return [pscustomobject]@{ Installed = $false; Version = $null; Products = $null; Platform = $null; UpdateUrl = $null; UpdatesEnabled = $null; CDNBaseUrl = $null; LanguageFolders = ($cultures -join ',') }
    }
    $value = { param($name) if ($c2r.PSObject.Properties[$name]) { $c2r.$name } else { $null } }
    [pscustomobject]@{
        Installed       = $true
        Version         = & $value 'VersionToReport'
        Products        = & $value 'ProductReleaseIds'
        Platform        = & $value 'Platform'
        UpdateUrl       = & $value 'UpdateUrl'
        UpdatesEnabled  = & $value 'UpdatesEnabled'
        CDNBaseUrl      = & $value 'CDNBaseUrl'
        LanguageFolders = ($cultures -join ',')
    }
}

function Get-StoreOfficeApp {
    <#
    .SYNOPSIS
        Liste, en lecture seule, les applications du Store liées à Office (application Microsoft 365, Office Hub).
    #>
    [CmdletBinding()]
    param()
    @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Office|Microsoft365|OfficeHub' } |
        ForEach-Object { '{0} {1}' -f $_.Name, $_.Version }) -join '; '
}

function Set-OfficeCdnBlock {
    <#
    .SYNOPSIS
        Bloque ou rétablit les domaines du CDN Office dans le fichier hosts (runner uniquement).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][string]$BackupPath,
        [string[]]$BlockedHost = @('officecdn.microsoft.com', 'f.c2r.ts.cdn.office.net')
    )
    $hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (-not $PSCmdlet.ShouldProcess($hostsFile, 'Blocage du CDN Office')) { return }
    if ($Enabled) {
        Copy-Item -Path $hostsFile -Destination $BackupPath -Force
        Add-Content -Path $hostsFile -Value (($BlockedHost | ForEach-Object { "0.0.0.0 $_" }) -join "`r`n") -Encoding ASCII
    } elseif (Test-Path $BackupPath) {
        Copy-Item -Path $BackupPath -Destination $hostsFile -Force
    }
    & ipconfig.exe /flushdns | Out-Null
}

function Get-OdtConfigurationXml {
    <#
    .SYNOPSIS
        Construit un XML de configuration de l'ODT (Add, Remove, Updates) pour les essais.
    #>
    [CmdletBinding()]
    param(
        [string]$SourcePath,
        [string]$Channel = 'Current',
        [string]$ProductId,
        [string[]]$Language = @('fr-fr'),
        [string]$Version,
        [switch]$NoCdnFallback,
        [switch]$RemoveAll,
        [switch]$Display
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<Configuration>')
    if ($ProductId) {
        $attributes = 'OfficeClientEdition="64" Channel="' + $Channel + '"'
        if ($SourcePath) { $attributes += ' SourcePath="' + $SourcePath + '"' }
        if ($Version) { $attributes += ' Version="' + $Version + '"' }
        if ($NoCdnFallback) { $attributes += ' AllowCdnFallback="FALSE"' }
        [void]$sb.AppendLine("  <Add $attributes>")
        [void]$sb.AppendLine("    <Product ID=""$ProductId"">")
        foreach ($l in $Language) { [void]$sb.AppendLine("      <Language ID=""$l"" />") }
        [void]$sb.AppendLine('    </Product>')
        [void]$sb.AppendLine('  </Add>')
    }
    if ($RemoveAll) { [void]$sb.AppendLine('  <Remove All="TRUE" />') }
    if ($Display) {
        [void]$sb.AppendLine('  <Display Level="None" AcceptEULA="TRUE" />')
    }
    [void]$sb.Append('</Configuration>')
    $sb.ToString()
}
