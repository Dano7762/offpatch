function ConvertFrom-OpReleaseInformationPage {
    <#
    .SYNOPSIS
        Extrait la correspondance KB → UBR d'une page release-information de Windows (learn.microsoft.com).

    .DESCRIPTION
        Fonction pure, sans accès réseau. La page publie l'historique des cumulatives sous forme de tableaux dont
        chaque ligne porte une cellule de build (« 19045.<UBR> ») et un lien vers l'article (« KB<n> »), relevé
        le 2026-10-11 (R-01). Seules les lignes de la build de base demandée sont retenues : un même KB figure aussi
        sous d'autres builds (19044 pour les éditions LTSC). Renvoie un dictionnaire KB → UBR ; une page sans
        aucune ligne pour cette build lève une erreur explicite plutôt que de renvoyer un dictionnaire vide.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, int]])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Html,
        [Parameter(Mandatory)][ValidateRange(10000, 99999)][int]$BaseBuild
    )

    $result = New-Object 'System.Collections.Generic.Dictionary[string, int]'
    foreach ($row in [regex]::Matches($Html, '(?s)<tr>(.*?)</tr>')) {
        $build = [regex]::Match($row.Groups[1].Value, '<td>\s*(\d{5})\.(\d+)\s*</td>')
        $kb = [regex]::Match($row.Groups[1].Value, '>\s*(KB\d+)\s*</a>')
        if (-not $build.Success -or -not $kb.Success -or [int]$build.Groups[1].Value -ne $BaseBuild) { continue }
        # La ligne la plus haute du tableau est la plus récente : un KB republié garde sa première valeur.
        if (-not $result.ContainsKey($kb.Groups[1].Value)) { $result.Add($kb.Groups[1].Value, [int]$build.Groups[2].Value) }
    }
    if ($result.Count -eq 0) {
        throw "Page release-information non reconnue : aucune ligne « $BaseBuild.<UBR> » associée à un KB."
    }
    $result
}
