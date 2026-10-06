# Module OffPatch : charge les fonctions internes (Private/) puis les fonctions exportées (Public/), une par fichier.
# Seules les fonctions de Public/ sont exportées, d'après le nom de leur fichier.
Set-StrictMode -Version Latest

foreach ($folder in 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path -Path $path -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -Path $path -Filter '*.ps1' -File | Sort-Object Name)) {
        try {
            . $file.FullName
        } catch {
            throw "Chargement du module OffPatch impossible : erreur dans $($file.Name) : $($_.Exception.Message)"
        }
    }
}

$publicFolder = Join-Path $PSScriptRoot 'Public'
$publicFunctions = @()
if (Test-Path -Path $publicFolder -PathType Container) {
    $publicFunctions = @(Get-ChildItem -Path $publicFolder -Filter '*.ps1' -File | ForEach-Object { $_.BaseName })
}
Export-ModuleMember -Function $publicFunctions
