function Get-OpWindows10ReleaseInfo {
    <#
    .SYNOPSIS
        Télécharge la page release-information de Windows 10 et renvoie la correspondance KB → UBR.

    .DESCRIPTION
        Lecture seule (cahier des charges 6.2, R-01, R-09). Le titre de la cumulative Windows 10 au catalogue ne
        porte pas de build : l'UBR qui sert à la sélection (pick = highestUbrFromReleaseInformation) est lu sur
        la page release-information, dont l'adresse est dans settings.json (downloadPages.windows10ReleaseInformation)
        et la build de base dans catalog-queries.json (releaseInformationBuild). La page passe par
        Invoke-OpWebRequest (nouvelles tentatives) ; une page non reconnue lève une erreur qui donne l'URL.
        Renvoie un dictionnaire KB → UBR (entier).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, int]])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [Parameter(Mandatory)][ValidateRange(10000, 99999)][int]$BaseBuild
    )

    $html = Invoke-OpWebRequest -Uri $Uri
    try {
        ConvertFrom-OpReleaseInformationPage -Html $html -BaseBuild $BaseBuild
    } catch {
        throw ('{0} URL {1}.' -f $_.Exception.Message, $Uri)
    }
}
