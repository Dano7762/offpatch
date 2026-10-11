# Contrat avec le Microsoft Update Catalog en ligne (R-11, R-13) : les fonctions de production doivent reconnaître
# les pages actuelles du site, et les liens du moment rester dans allowedDomains. Lecture seule, aucun téléchargement
# de fichier. Tag Live : exclu de ci.yml et de la vérification avant push, lancé chaque mercredi et à la demande par
# catalog-contract.yml. Pas de nouvelle tentative propre au test : les requêtes passent par la politique du code de
# production (Invoke-OpWebRequest). En cas d'échec, le message (code HTTP, URL, extrait de la page) est enregistré
# dans le dossier OFFPATCH_DIAGNOSTIC_DIR s'il est défini (artefact du workflow).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertFrom-OpCatalogSearchPage', 'ConvertFrom-OpCatalogDownloadDialog', 'Invoke-OpWebRequest', 'Find-OpCatalogUpdate',
        'Get-OpCatalogDownloadLink', 'Invoke-OpHeadRequest', 'Resolve-OpDownloadUrl', 'ConvertFrom-OpReleaseInformationPage',
        'Get-OpWindows10ReleaseInfo', 'Select-OpCatalogUpdate', 'Get-OpCatalogSelection', 'Get-OpDefenderDefinitionPlan', 'Write-OpLog', 'ConvertTo-OpMaskedText') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $settings = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $pinned = (Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    function Save-LiveDiagnostic([string]$Test, [string]$Message) {
        if (-not $env:OFFPATCH_DIAGNOSTIC_DIR) { return }
        New-Item -ItemType Directory -Force -Path $env:OFFPATCH_DIAGNOSTIC_DIR | Out-Null
        $line = '{0:yyyy-MM-ddTHH:mm:ssZ} | {1} | {2}' -f (Get-Date).ToUniversalTime(), $Test, $Message
        Add-Content -Path (Join-Path $env:OFFPATCH_DIAGNOSTIC_DIR 'echecs.txt') -Value $line -Encoding UTF8
    }
}

Describe 'Microsoft Update Catalog en ligne' -Tag 'Live' {
    It 'la recherche par KB et la fenêtre de téléchargement sont toujours reconnues' {
        try {
            $entry = Find-OpCatalogUpdate -Query 'KB5043080' | Where-Object { $_.Title -match 'Windows 11 Version 24H2 for x64-based Systems \(KB5043080\)' } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty
            $files = @(Get-OpCatalogDownloadLink -UpdateId $entry.UpdateId)
            ($files | Where-Object { $_.FileName -match '^windows11\.0-kb5043080-x64_[0-9a-f]{40}\.msu$' }) | Should -Not -BeNullOrEmpty
        } catch {
            Save-LiveDiagnostic -Test 'recherche et fenêtre' -Message $_.Exception.Message
            throw
        }
    }

    It 'la pagination (&p=) ramène toutes les lignes annoncées par le compteur' {
        try {
            $query = '2026-09 Cumulative Update Windows 11'
            $first = ConvertFrom-OpCatalogSearchPage -Html (Invoke-OpWebRequest -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($query)))
            $first.HasNextPage | Should -BeTrue
            @(Find-OpCatalogUpdate -Query $query).Count | Should -Be $first.TotalCount
        } catch {
            Save-LiveDiagnostic -Test 'pagination' -Message $_.Exception.Message
            throw
        }
    }
}

# R-13 : liens réels du moment, redirections comprises, résolus par Resolve-OpDownloadUrl sans rien télécharger
# (requêtes HEAD). Un hôte absent de allowedDomains fait échouer le test avec la ligne à ajouter.
# Les liens de mpam-fe.exe et de la page de l'ODT sont lus dans settings.json (downloadPages).
Describe 'Hôtes des téléchargements du moment' -Tag 'Live' {
    It 'chaque lien et chaque redirection restent dans allowedDomains' {
        try {
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
                foreach ($f in Get-OpCatalogDownloadLink -UpdateId $entry.UpdateId) { $urls.Add($f.Url) }
            }
            foreach ($p in $pinned) { $urls.Add($p.url) }
            foreach ($link in $settings.downloadPages.defenderDefinitions.PSObject.Properties) { $urls.Add($link.Value) }
            $odtPage = $settings.downloadPages.officeDeploymentToolPage
            Resolve-OpDownloadUrl -Url 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB4052623' -AllowedDomain $settings.allowedDomains | Out-Null
            $page = Invoke-OpWebRequest -Uri $odtPage
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
        } catch {
            Save-LiveDiagnostic -Test 'hôtes des liens' -Message $_.Exception.Message
            throw
        }
    }
}

# Définitions Defender (R-06) : l'URL finale du lien officiel doit toujours porter la version (packageVersion) et
# l'architecture (arch), seul moyen de savoir si le dépôt est à jour sans télécharger mpam-fe.exe.
Describe 'Version des définitions Defender' -Tag 'Live' {
    It 'le lien de chaque architecture donne la version dans son URL finale' {
        try {
            $configuration = [pscustomobject]@{ Settings = $settings }
            $empty = [pscustomobject]@{ schemaVersion = 1; items = @() }
            foreach ($arch in $settings.downloadPages.defenderDefinitions.PSObject.Properties.Name) {
                $item = Get-OpDefenderDefinitionPlan -Configuration $configuration -Manifest $empty -Target "win11-$arch"
                Write-Host ('{0} : version {1}, {2} octets' -f $arch, $item.Version, $item.Files[0].SizeBytes)
                $item.Files[0].Error | Should -BeNullOrEmpty
                $item.Version | Should -Not -BeNullOrEmpty
            }
        } catch {
            Save-LiveDiagnostic -Test 'version des définitions Defender' -Message $_.Exception.Message
            throw
        }
    }
}

# Sélection du mois (cahier des charges 6.2) : pour chaque cible de settings.json, chaque entrée de
# catalog-queries.json doit retenir un KB, et la cumulative Windows 10 son UBR publié sur release-information.
Describe 'Sélection du mois' -Tag 'Live' {
    It 'chaque catégorie de chaque cible retient un élément' {
        try {
            $configuration = [pscustomobject]@{
                Settings       = $settings
                CatalogQueries = Get-Content -Path (Join-Path $root 'config\catalog-queries.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            $missing = @(foreach ($target in $settings.targets) {
                    foreach ($s in Get-OpCatalogSelection -Configuration $configuration -Target $target) {
                        Write-Host ('{0} / {1} : {2} {3} {4}' -f $target, $s.Category, $s.Kb, $s.ResultingUbr, $s.Version)
                        if (-not $s.Kb) { "$target / $($s.Category) : aucun élément retenu" }
                        elseif ($s.Pick -match '^highestUbr' -and $null -eq $s.ResultingUbr) { "$target / $($s.Category) : UBR inconnu ($($s.Warnings -join ' '))" }
                    }
                })
            $missing | Should -BeNullOrEmpty
        } catch {
            Save-LiveDiagnostic -Test 'sélection du mois' -Message $_.Exception.Message
            throw
        }
    }
}
