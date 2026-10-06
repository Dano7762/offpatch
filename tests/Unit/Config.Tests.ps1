# Cohérence des fichiers de config/ entre eux (bilan de phase 0). Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    function Read-Config([string]$Path) { Get-Content -Path (Join-Path $root $Path) -Raw -Encoding UTF8 | ConvertFrom-Json }
    $settings = Read-Config 'config\settings.json'
    $queries = Read-Config 'config\catalog-queries.json'
    $profiles = (Read-Config 'config\office\profiles.json').profiles
    $categories = 'windows-lcu', 'windows-checkpoint', 'windows-ekb', 'windows-ssu', 'dotnet', 'defender-platform', 'defender', 'office-source'
}

Describe 'config/settings.json' {
    It 'donne une rétention Windows d''au moins 1 mois pour chaque cible' {
        foreach ($t in $settings.targets) {
            $settings.retention.windowsMonths.PSObject.Properties[$t] | Should -Not -BeNullOrEmpty -Because "la cible $t doit avoir sa rétention"
            [int]$settings.retention.windowsMonths.$t | Should -BeGreaterOrEqual 1
        }
    }

    It 'liste des hôtes exacts, sans joker ni schéma' {
        foreach ($d in $settings.allowedDomains) { $d | Should -Match '^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$' }
    }

    It 'donne des liens downloadPages en https sur des hôtes autorisés, avec un lien de définitions par architecture de cible' {
        $links = @($settings.downloadPages.defenderDefinitions.PSObject.Properties | ForEach-Object { $_.Value }) + $settings.downloadPages.officeDeploymentToolPage
        foreach ($l in $links) {
            ([uri]$l).Scheme | Should -Be 'https'
            $settings.allowedDomains | Should -Contain ([uri]$l).Host
        }
        foreach ($t in $settings.targets) {
            $arch = ($t -split '-')[1]
            $settings.downloadPages.defenderDefinitions.PSObject.Properties[$arch] | Should -Not -BeNullOrEmpty -Because "la cible $t doit avoir son lien de définitions"
        }
    }

    It 'déclare au moins une empreinte de racine de 40 caractères hexadécimaux' {
        @($settings.integrity.trustedRootThumbprints).Count | Should -BeGreaterThan 0
        foreach ($t in $settings.integrity.trustedRootThumbprints) { $t | Should -Match '^[0-9A-F]{40}$' }
    }
}

Describe 'config/catalog-queries.json' {
    It 'couvre chaque cible de settings.json' {
        foreach ($t in $settings.targets) { $queries.targets.PSObject.Properties[$t] | Should -Not -BeNullOrEmpty -Because "la cible $t doit avoir ses recherches" }
    }

    It 'n''utilise que des catégories connues, des motifs valides et des dépendances vers des catégories connues' {
        foreach ($target in $queries.targets.PSObject.Properties) {
            foreach ($q in $target.Value) {
                $categories | Should -Contain $q.category
                @($q.searches).Count | Should -BeGreaterThan 0
                { [regex]::new($q.includeTitlePattern) } | Should -Not -Throw
                { [regex]::new($q.excludeTitlePattern) } | Should -Not -Throw
                $q.pick | Should -BeIn @('latestMonth', 'highestUbr', 'highestUbrFromReleaseInformation', 'highestVersion')
                foreach ($d in @($q.prerequisites) + @($q.runsAfter)) { if ($d) { $categories | Should -Contain $d } }
            }
        }
    }
}

Describe 'config/office/profiles.json' {
    It 'a des identifiants uniques et des sources déclarées dans settings.json' {
        @($profiles.id | Sort-Object -Unique).Count | Should -Be @($profiles).Count
        foreach ($p in $profiles) {
            $settings.office.sources.PSObject.Properties[$p.source] | Should -Not -BeNullOrEmpty -Because "le profil $($p.id) utilise la source $($p.source)"
        }
    }

    It 'n''accepte une clé de produit que pour les licences en volume' {
        foreach ($p in $profiles) { [bool]$p.acceptsProductKey | Should -Be ($p.license -eq 'volume') }
    }

    It 'cite une source Microsoft pour la prise en charge' {
        foreach ($p in $profiles) { $p.supportedOn.source | Should -Match '^https://support\.microsoft\.com/' }
    }
}
