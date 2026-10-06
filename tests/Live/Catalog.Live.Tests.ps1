# Contrat avec le Microsoft Update Catalog en ligne (R-11) : les fonctions d'analyse doivent reconnaître les pages
# actuelles du site. Lecture seule, quelques requêtes, aucun téléchargement de fichier. Tag Live : exclu de ci.yml,
# lancé chaque mercredi et à la demande par catalog-contract.yml.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogSearchPage.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogDownloadDialog.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\Find-OpCatalogUpdate.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\Invoke-OpHeadRequest.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\Resolve-OpDownloadUrl.ps1')
    $settings = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $pinned = (Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items
    function Get-DialogUrl([string]$UpdateId) {
        $body = 'updateIDs=' + [uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]')
        $dialog = (Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop).Content
        @(ConvertFrom-OpCatalogDownloadDialog -Html $dialog | ForEach-Object { $_.Url })
    }
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

    It 'la pagination (&p=) ramène toutes les lignes annoncées par le compteur' {
        $query = '2026-09 Cumulative Update Windows 11'
        $first = ConvertFrom-OpCatalogSearchPage -Html (Invoke-WebRequest -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($query)) -UseBasicParsing -ErrorAction Stop).Content
        $first.HasNextPage | Should -BeTrue
        @(Find-OpCatalogUpdate -Query $query).Count | Should -Be $first.TotalCount
    }
}

# R-13 : liens réels du moment, redirections comprises, résolus par Resolve-OpDownloadUrl sans rien télécharger
# (requêtes HEAD). Un hôte absent de allowedDomains fait échouer le test avec la ligne à ajouter.
# Les liens de mpam-fe.exe et de la page de l'ODT sont écrits ici en attendant leur place dans config/ (phase 2).
Describe 'Hôtes des téléchargements du moment' -Tag 'Live' {
    It 'chaque lien et chaque redirection restent dans allowedDomains' {
        $urls = New-Object System.Collections.Generic.List[string]
        $searches = @(
            @('Cumulative Update for Windows 11, version 25H2 for x64-based Systems', 'Cumulative Update for Windows 11, version 25H2 for x64-based'),
            @('Cumulative Update for Windows 11, version 25H2 for arm64-based Systems', 'Cumulative Update for Windows 11, version 25H2 for arm64-based'),
            @('Cumulative Update for Windows 10 Version 22H2 for x64-based Systems', 'Cumulative Update for Windows 10 Version 22H2 for x64-based'),
            @('Cumulative Update for .NET Framework Windows 11, version 24H2 x64', '\.NET Framework 3\.5 and 4\.8\.1 for Windows 11, version 24H2 for x64'),
            @('Cumulative Update for .NET Framework Windows 10 Version 22H2 x64', '\.NET Framework 3\.5, 4\.8 and 4\.8\.1 for Windows 10 Version 22H2 for x64'),
            @('KB4052623', 'Current Channel \(Broad\)')
        )
        foreach ($s in $searches) {
            $entry = Find-OpCatalogUpdate -Query $s[0] | Where-Object { $_.Title -match $s[1] -and $_.Title -notmatch 'Preview|Dynamic' } |
                Sort-Object LastUpdated -Descending | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty -Because "la recherche « $($s[0]) » doit trouver une entrée"
            foreach ($u in Get-DialogUrl -UpdateId $entry.UpdateId) { $urls.Add($u) }
        }
        foreach ($p in $pinned) { $urls.Add($p.url) }
        foreach ($arch in 'x64', 'arm64') { $urls.Add("https://go.microsoft.com/fwlink/?LinkID=121721&arch=$arch") }
        $odtPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'
        Resolve-OpDownloadUrl -Url 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB4052623' -AllowedDomain $settings.allowedDomains | Out-Null
        $page = (Invoke-WebRequest -Uri $odtPage -UseBasicParsing -ErrorAction Stop).Content
        $odt = [regex]::Matches($page, 'https://download\.microsoft\.com/[^"\\ ]+officedeploymenttool[^"\\ ]+\.exe') | ForEach-Object { $_.Value } | Select-Object -First 1
        $odt | Should -Not -BeNullOrEmpty -Because 'la page de l''ODT doit donner le lien du fichier'
        $urls.Add($odtPage)
        $urls.Add($odt)

        $failures = @(foreach ($u in $urls) {
                try {
                    $r = Resolve-OpDownloadUrl -Url $u -AllowedDomain $settings.allowedDomains
                    Write-Host ('{0} -> {1}' -f $u, ($r.Hosts -join ' -> '))
                } catch { $_.Exception.Message }
            })
        $failures | Should -BeNullOrEmpty
    }
}
