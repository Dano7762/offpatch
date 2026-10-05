# Contrat avec le Microsoft Update Catalog en ligne (R-11) : les fonctions d'analyse doivent reconnaître les pages
# actuelles du site. Lecture seule, deux requêtes, aucun téléchargement de fichier. Tag Live : lancé par une étape
# dédiée de la CI, pour qu'une casse du site se voie dès le push suivant.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogSearchPage.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogDownloadDialog.ps1')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

Describe 'Microsoft Update Catalog en ligne' -Tag 'Live' {
    It 'la recherche par KB et la fenêtre de téléchargement sont toujours reconnues' {
        $html = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB5043080' -UseBasicParsing -ErrorAction Stop).Content
        $page = ConvertFrom-OpCatalogSearchPage -Html $html
        $entry = $page.Items | Where-Object { $_.Title -match 'Windows 11 Version 24H2 for x64-based Systems \(KB5043080\)' } | Select-Object -First 1
        $entry | Should -Not -BeNullOrEmpty

        $body = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $entry.UpdateId + '","updateID":"' + $entry.UpdateId + '"}]')
        $dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop).Content
        $files = @(ConvertFrom-OpCatalogDownloadDialog -Html $dialog)
        ($files | Where-Object { $_.FileName -match '^windows11\.0-kb5043080-x64_[0-9a-f]{40}\.msu$' }) | Should -Not -BeNullOrEmpty
    }
}
