# Analyse des pages du Microsoft Update Catalog sur des pages réelles enregistrées (tests/Fixtures/catalog, R-11).
# Aucun accès réseau. Les fixtures se rafraîchissent avec tests/Fixtures/catalog/Save-CatalogFixture.ps1.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogSearchPage.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\ConvertFrom-OpCatalogDownloadDialog.ps1')
    $fixtures = Join-Path $root 'tests\Fixtures\catalog'
    function Read-Fixture([string]$Name) { [System.IO.File]::ReadAllText((Join-Path $fixtures $Name)) }
}

Describe 'ConvertFrom-OpCatalogSearchPage' {
    Context 'Recherche KB5129195 (page réelle)' {
        BeforeAll { $page = ConvertFrom-OpCatalogSearchPage -Html (Read-Fixture 'search-kb5129195.html') }

        It 'trouve les six entrées Windows 11 de la cumulative' {
            $page.NoResults | Should -BeFalse
            @($page.Items | Where-Object { $_.Title -match '^2026-09 Cumulative Update for Windows 11, version (24H2|25H2|26H2) for (x64|arm64)-based Systems \(KB5129195\) \(\d+\.9457\)$' }).Count | Should -Be 6
        }

        It 'relève un identifiant, une date et une taille en octets pour chaque entrée' {
            foreach ($item in $page.Items) {
                $item.UpdateId | Should -Match '^[0-9a-f\-]{36}$'
                $item.LastUpdated | Should -BeOfType [datetime]
                $item.SizeBytes | Should -BeGreaterThan 0
            }
        }

        It 'ne laisse pas d''entité HTML dans les titres' {
            foreach ($item in $page.Items) { $item.Title | Should -Not -Match '&nbsp;|&amp;|<' }
        }
    }

    Context 'Recherche large (page pleine)' {
        It 'signale une page de 25 lignes, risque de troncature' {
            $page = ConvertFrom-OpCatalogSearchPage -Html (Read-Fixture 'search-full.html')
            $page.Items.Count | Should -Be 25
            $page.IsFull | Should -BeTrue
        }
    }

    Context 'Recherche sans résultat' {
        It 'reconnaît la page « aucun résultat » sans erreur' {
            $page = ConvertFrom-OpCatalogSearchPage -Html (Read-Fixture 'search-noresult.html')
            $page.NoResults | Should -BeTrue
            $page.Items.Count | Should -Be 0
        }
    }

    Context 'Page inattendue' {
        It 'lève une erreur explicite plutôt que de renvoyer une liste vide' {
            { ConvertFrom-OpCatalogSearchPage -Html '<html><body>Maintenance</body></html>' } | Should -Throw -ExpectedMessage '*non reconnue*'
        }
    }
}

Describe 'ConvertFrom-OpCatalogDownloadDialog' {
    It 'extrait la cumulative et la checkpoint de la fenêtre réelle, avec le SHA-1 du nom' {
        $files = @(ConvertFrom-OpCatalogDownloadDialog -Html (Read-Fixture 'dialog-kb5129195.html'))
        $files.Count | Should -Be 2
        ($files | Where-Object { $_.FileName -match '^windows11\.0-kb5129195-x64_' }).Sha1 | Should -Match '^[0-9a-f]{40}$'
        ($files | Where-Object { $_.FileName -match '^windows11\.0-kb5043080-x64_' }) | Should -Not -BeNullOrEmpty
        foreach ($f in $files) { ([uri]$f.Url).Host | Should -Be 'catalog.sf.dl.delivery.mp.microsoft.com' }
    }

    It 'lève une erreur explicite sur une fenêtre sans lien' {
        { ConvertFrom-OpCatalogDownloadDialog -Html '<html></html>' } | Should -Throw -ExpectedMessage '*non reconnue*'
    }
}
