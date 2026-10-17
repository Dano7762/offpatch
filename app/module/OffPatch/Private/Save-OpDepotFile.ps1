function Save-OpDepotFile {
    <#
    .SYNOPSIS
        Télécharge un fichier de la liste du dépôt, le contrôle et le range dans files/<sha256>/<nom d'origine>.

    .DESCRIPTION
        Étapes 4 à 7 de la mise à jour du dépôt (cahier des charges 7.1, section 5) pour un fichier de Get-OpDepotPlan :
          1. téléchargement dans depot/.tmp/<repère de l'URL>/<nom> (Save-OpDownload, taille annoncée contrôlée) ;
             le repère, tiré de l'URL, sépare deux fichiers de même nom (mpam-fe.exe x64 et ARM64) et reste stable
             d'un lancement à l'autre pour la reprise ;
          2. signature, SHA-1 publié et SHA-256 (Confirm-OpDownloadIntegrity) ;
          3. Defender (plateforme et définitions) : FileVersion égale à la version annoncée par le catalogue ou par le
             lien, sinon fichier supprimé et erreur ;
          4. cumulative Windows ou .NET (.msu) : nom et version du paquet (Read-OpMsuPackage) ;
          5. déplacement dans files/<sha256>/ ; un fichier déjà rangé sous le même SHA-256 est gardé tel quel.
        Renvoie l'entrée de fichier du manifeste : path (relatif à depot/), sha256, size, package ($null si absent).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][pscustomobject]$File,
        [Parameter(Mandatory)][pscustomobject]$Configuration,
        [Parameter(Mandatory)][string]$Root
    )

    if (-not $PSCmdlet.ShouldProcess($File.Url, "Téléchargement et rangement de $($File.FileName)")) { return }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $key = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($File.Url))[0..7] | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
    $work = Join-Path (Get-OpPath -Name DepotTemp -Root $Root) $key
    $temp = Join-Path $work $File.FileName

    Save-OpDownload -Url $File.Url -Destination $temp -ExpectedSize $File.SizeBytes -Confirm:$false | Out-Null
    $check = Confirm-OpDownloadIntegrity -Path $temp -TrustedRootThumbprint @($Configuration.Settings.integrity.trustedRootThumbprints) -ExpectedSha1 $File.Sha1 -Confirm:$false

    if (@('defender', 'defender-platform') -contains $Item.Category -and $null -ne $Item.Version) {
        $fileVersion = Get-OpFileVersion -Path $temp
        if ([string]$fileVersion -ne [string]$Item.Version) {
            Remove-Item -LiteralPath $temp -Force
            throw "Fichier refusé, $($File.FileName) : version $fileVersion, $($Item.Version) annoncée. Fichier supprimé."
        }
    }

    $package = $null
    if (@('windows-lcu', 'dotnet') -contains $Item.Category -and $File.FileName -match '(?i)\.msu$') {
        $package = Read-OpMsuPackage -Path $temp -WorkFolder ($temp + '.inspect') -Confirm:$false
        if ($package) { Write-OpLog "Dépôt : $($File.FileName), paquet $($package.name) $($package.version)." }
        elseif ($Item.Category -eq 'dotnet') {
            # La détection de .NET repose sur ce paquet (8.3) : sans lui, l'élément ne peut pas entrer au manifeste.
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            throw "Fichier refusé, $($File.FileName) : nom et version du paquet illisibles dans le .msu, indispensables à la détection de .NET. Fichier supprimé."
        }
    }

    $folder = Join-Path (Get-OpPath -Name DepotFiles -Root $Root) $check.Sha256
    $final = Join-Path $folder $File.FileName
    if (Test-Path -LiteralPath $final -PathType Leaf) {
        Remove-Item -LiteralPath $temp -Force
    } else {
        New-Item -ItemType Directory -Force -Path $folder -ErrorAction Stop | Out-Null
        Move-Item -LiteralPath $temp -Destination $final -ErrorAction Stop
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        path    = "files/$($check.Sha256)/$($File.FileName)"
        sha256  = $check.Sha256
        size    = (Get-Item -LiteralPath $final).Length
        package = $package
    }
}
