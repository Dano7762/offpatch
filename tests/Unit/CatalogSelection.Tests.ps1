# Sélection dans le catalogue selon catalog-queries.json (cahier des charges 6.2, R-01, R-05, R-06) : motifs et règles
# de sélection appliqués aux entrées réelles de config/, sur des titres relevés au catalogue ; page release-information
# enregistrée (tests/Fixtures/catalog). Aucun accès réseau : Find-OpCatalogUpdate et la page sont simulés.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    # Comme dans le module (OffPatch.psm1) : un accès hors limites ou à une propriété absente doit échouer ici aussi.
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertFrom-OpCatalogSearchPage', 'ConvertFrom-OpReleaseInformationPage', 'Get-OpWindows10ReleaseInfo', 'Invoke-OpWebRequest',
        'Find-OpCatalogUpdate', 'Select-OpCatalogUpdate', 'Get-OpCatalogSelection', 'Write-OpLog', 'ConvertTo-OpMaskedText') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $fixtures = Join-Path $root 'tests\Fixtures\catalog'
    function Read-Fixture([string]$Name) { [System.IO.File]::ReadAllText((Join-Path $fixtures $Name)) }
    function Get-Configuration {
        [pscustomobject]@{
            Settings       = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            CatalogQueries = Get-Content -Path (Join-Path $root 'config\catalog-queries.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    function Get-Entry([string]$Target, [string]$Category) {
        (Get-Configuration).CatalogQueries.targets.$Target | Where-Object { $_.category -eq $Category }
    }
    $script:rowNumber = 0
    function Get-CatalogRow([string]$Title, [string]$Date = '2026-09-14') {
        $script:rowNumber++
        [pscustomobject]@{
            UpdateId       = '00000000-0000-0000-0000-{0:d12}' -f $script:rowNumber
            Title          = $Title
            Products       = ''
            Classification = 'Security Updates'
            LastUpdated    = [datetime]::ParseExact($Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            SizeText       = ''
            SizeBytes      = [int64]1000
        }
    }
    function Get-ReleaseMap([hashtable]$Values) {
        $map = New-Object 'System.Collections.Generic.Dictionary[string, int]'
        foreach ($k in $Values.Keys) { $map.Add($k, $Values[$k]) }
        , $map
    }
}

Describe 'ConvertFrom-OpReleaseInformationPage' {
    Context 'Page Windows 10 réelle (relevée le 2026-10-11)' {
        BeforeAll { $map = ConvertFrom-OpReleaseInformationPage -Html (Read-Fixture 'release-information.html') -BaseBuild 19045 }

        It 'associe chaque KB à son UBR pour la build 19045' {
            $map['KB5129236'] | Should -Be 7727
            $map['KB5122878'] | Should -Be 7725
            $map.Count | Should -BeGreaterThan 50
        }

        It 'ne retient que la build demandée : aucun KB de la 1607 (14393) dans la 19045' {
            $other = ConvertFrom-OpReleaseInformationPage -Html (Read-Fixture 'release-information.html') -BaseBuild 14393
            $other.Count | Should -BeGreaterThan 0
            @($other.Keys | Where-Object { $map.ContainsKey($_) }).Count | Should -Be 0
        }
    }

    It 'lève une erreur explicite sur une page sans ligne pour la build' {
        { ConvertFrom-OpReleaseInformationPage -Html '<html><table><tr><td>Maintenance</td></tr></table></html>' -BaseBuild 19045 } | Should -Throw -ExpectedMessage '*non reconnue*19045*'
    }
}

Describe 'Get-OpWindows10ReleaseInfo' {
    It 'lit la page de la configuration et donne l''URL en cas de page non reconnue' {
        Mock Invoke-OpWebRequest { '<html>Maintenance</html>' }
        { Get-OpWindows10ReleaseInfo -Uri 'https://learn.microsoft.com/page' -BaseBuild 19045 } | Should -Throw -ExpectedMessage '*https://learn.microsoft.com/page*'
    }
}

Describe 'Select-OpCatalogUpdate' {
    Context 'highestUbr : cumulative Windows 11 sur les titres réels de KB5129195' {
        BeforeAll {
            $real = (ConvertFrom-OpCatalogSearchPage -Html (Read-Fixture 'search-kb5129195.html')).Items
            $rows = @($real) + @(
                Get-CatalogRow '2026-09 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5124008) (26200.9445)' '2026-09-08'
                Get-CatalogRow '2026-09 Cumulative Update Preview for Windows 11, version 25H2 for x64-based Systems (KB5124010) (26200.9550)' '2026-09-22'
                Get-CatalogRow '2026-09 Cumulative Update for Windows 11, version 26H1 for x64-based Systems (KB5129194) (28000.9999)'
                Get-CatalogRow '2026-08 Cumulative Update for Windows 11, version 24H2 for x64-based Systems (KB5120001) (26100.9300)' '2026-08-11'
            )
            $x64 = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'windows-lcu')
            $arm64 = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-arm64' 'windows-lcu')
        }

        It 'retient le KB dont l''UBR est le plus élevé, sans préversion ni 26H1' {
            $x64.Kb | Should -Be 'KB5129195'
            $x64.ResultingUbr | Should -Be 9457
            $x64.Warnings | Should -BeNullOrEmpty
        }

        It 'réunit les trois versions sous un seul élément, builds de base comprises' {
            @($x64.Entries).Count | Should -Be 3
            $x64.BaseBuilds | Should -Be @(26100, 26200, 26300)
            $x64.Title | Should -Match 'for x64-based Systems \(KB5129195\)'
            $x64.UpdateId | Should -Match '^[0-9a-f\-]{36}$'
        }

        It 'sépare les architectures' {
            $arm64.Kb | Should -Be 'KB5129195'
            @($arm64.Entries | Where-Object { $_.Title -notmatch 'arm64-based' }).Count | Should -Be 0
        }

        It 'recopie les dépendances de l''entrée' {
            $x64.Prerequisites | Should -Be @('windows-checkpoint')
            @($x64.RunsAfter).Count | Should -Be 0
            $x64.Category | Should -Be 'windows-lcu'
        }

        It 'retient un OOB du mois plutôt que la cumulative du Patch Tuesday' {
            $x64.Kb | Should -Not -Be 'KB5124008'
        }
    }

    Context 'highestUbr : cas limites' {
        It 'passe l''année : décembre et janvier fusionnés, UBR le plus élevé' {
            $rows = @(
                Get-CatalogRow '2026-12 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5130001) (26200.9900)' '2026-12-08'
                Get-CatalogRow '2027-01 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5130002) (26200.9950)' '2027-01-12'
            )
            (Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'windows-lcu')).Kb | Should -Be 'KB5130002'
        }

        It 'avertit quand un même KB est cité avec deux UBR' {
            $rows = @(
                Get-CatalogRow '2026-10 Cumulative Update for Windows 11, version 24H2 for x64-based Systems (KB5130003) (26100.9600)'
                Get-CatalogRow '2026-10 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5130003) (26200.9601)'
            )
            $s = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'windows-lcu')
            $s.ResultingUbr | Should -Be 9601
            ($s.Warnings -join ' ') | Should -BeLike '*plusieurs UBR*'
        }

        It 'renvoie un élément vide avec un avertissement quand rien ne correspond' {
            $s = Select-OpCatalogUpdate -Item @() -Entry (Get-Entry 'win11-x64' 'windows-lcu')
            $s.Kb | Should -BeNullOrEmpty
            @($s.Entries).Count | Should -Be 0
            ($s.Warnings -join ' ') | Should -BeLike '*aucune entrée*'
        }
    }

    Context 'highestUbrFromReleaseInformation : cumulative Windows 10' {
        BeforeAll {
            $rows = @(
                Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5122878)' '2026-09-08'
                Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5129236)' '2026-09-14'
                Get-CatalogRow '2026-08 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5120249)' '2026-08-11'
                Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 21H2 for x64-based Systems (KB5129236)'
                Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 22H2 for ARM64-based Systems (KB5129236)'
            )
            $entry = Get-Entry 'win10-x64' 'windows-lcu'
        }

        It 'retient le KB dont l''UBR publié est le plus élevé (page réelle)' {
            $map = ConvertFrom-OpReleaseInformationPage -Html (Read-Fixture 'release-information.html') -BaseBuild 19045
            $s = Select-OpCatalogUpdate -Item $rows -Entry $entry -ReleaseInformation $map
            $s.Kb | Should -Be 'KB5129236'
            $s.ResultingUbr | Should -Be 7727
            $s.BaseBuilds | Should -Be @(19045)
            @($s.Entries).Count | Should -Be 1
            $s.Warnings | Should -BeNullOrEmpty
        }

        It 'se replie sur le mois du titre, avec un avertissement, si aucun KB ne figure sur la page' {
            $s = Select-OpCatalogUpdate -Item $rows -Entry $entry -ReleaseInformation (Get-ReleaseMap @{ KB0000001 = 1 })
            $s.Month | Should -Be '2026-09'
            $s.ResultingUbr | Should -BeNullOrEmpty
            ($s.Warnings -join ' ') | Should -BeLike '*release-information*'
        }

        It 'se replie aussi sans page du tout' {
            $s = Select-OpCatalogUpdate -Item $rows -Entry $entry
            $s.Kb | Should -BeIn @('KB5122878', 'KB5129236')
            ($s.Warnings -join ' ') | Should -BeLike '*release-information*'
        }
    }

    Context 'latestMonth : cumulative .NET' {
        It 'retient le mois le plus récent et regroupe les trois versions de Windows 11 sans avertissement' {
            $rows = @(
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2 for x64 (KB5126052)' '2026-09-08'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126052)' '2026-09-08'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 26H2 for x64 (KB5126052)' '2026-09-29'
                Get-CatalogRow '2026-08 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5120500)' '2026-08-11'
                Get-CatalogRow '2026-09 Cumulative Update Preview for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126999)' '2026-09-22'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for arm64 (KB5126052)' '2026-09-08'
            )
            $s = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'dotnet')
            $s.Kb | Should -Be 'KB5126052'
            @($s.Entries).Count | Should -Be 3
            $s.ResultingUbr | Should -BeNullOrEmpty
            $s.Warnings | Should -BeNullOrEmpty
        }

        It 'garde un élément par KB quand Microsoft sépare les versions (octobre 2026), avec les builds de chacun' {
            $rows = @(
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2 for x64 (KB5127690)' '2026-10-13'
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5127690)' '2026-10-13'
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 26H2 for x64 (KB5127694)' '2026-10-13'
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Microsoft server operating system version 24H2 for x64 (KB5127690)' '2026-10-13'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126052)' '2026-09-08'
            )
            $s = @(Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'dotnet') | Sort-Object Kb)
            @($s.Kb) | Should -Be @('KB5127690', 'KB5127694')
            @($s[0].BaseBuilds) | Should -Be @(26100, 26200)
            @($s[1].BaseBuilds) | Should -Be @(26300)
            @($s[0].Entries).Count | Should -Be 2
            $s[0].Warnings | Should -BeNullOrEmpty
        }

        It 'écarte, avec un avertissement, un KB dont aucune version n''est dans versionBuilds' {
            $entry = Get-Entry 'win11-x64' 'dotnet'
            $entry.versionBuilds = [pscustomobject]@{ '25H2' = 26200 }
            $rows = @(
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5127690)' '2026-10-13'
                Get-CatalogRow '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 26H2 for x64 (KB5127694)' '2026-10-13'
            )
            $s = @(Select-OpCatalogUpdate -Item $rows -Entry $entry)
            @($s.Kb) | Should -Be @('KB5127690')
            ($s[0].Warnings -join ' ') | Should -BeLike '*KB5127694 écarté*26H2*versionBuilds*'
        }

        It 'retient l''entrée Windows 10 qui apporte les deux fichiers' {
            $rows = @(
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8 for Windows 10 Version 22H2 for x64 (KB5126046)'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 10 Version 22H2 for x64 (KB5126421)'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version 22H2 for x64 (KB5126146)'
            )
            (Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win10-x64' 'dotnet')).Kb | Should -Be 'KB5126146'
        }

        It 'départage deux KB du même mois par la date du catalogue, avec un avertissement' {
            $rows = @(
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126052)' '2026-09-08'
                Get-CatalogRow '2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126060)' '2026-09-20'
            )
            $s = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-x64' 'dotnet')
            $s.Kb | Should -Be 'KB5126060'
            ($s.Warnings -join ' ') | Should -BeLike '*égalité*date du catalogue*'
        }
    }

    Context 'highestVersion : plateforme Defender' {
        It 'retient la version la plus élevée du canal Broad et recopie le motif de fichier' {
            $rows = @(
                Get-CatalogRow 'Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.25080.5) - Current Channel (Broad)' '2026-08-20'
                Get-CatalogRow 'Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.26080.4) - Current Channel (Broad)' '2026-09-25'
                Get-CatalogRow 'Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.26090.1) - Current Channel (Preview)' '2026-10-01'
                Get-CatalogRow 'Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.25090.2) - Current Channel (Broad)' '2026-09-30'
            )
            $s = Select-OpCatalogUpdate -Item $rows -Entry (Get-Entry 'win11-arm64' 'defender-platform')
            $s.Kb | Should -Be 'KB4052623'
            $s.Version | Should -Be ([version]'4.18.26080.4')
            $s.FileNamePattern | Should -Be '^updateplatform\.arm64fre_[0-9a-f]{40}\.exe$'
            $s.Warnings | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-OpCatalogSelection' {
    BeforeAll {
        Mock Write-OpLog {}
    }

    Context 'Recherches envoyées' {
        BeforeAll {
            Mock Find-OpCatalogUpdate { @() }
            $result = @(Get-OpCatalogSelection -Configuration (Get-Configuration) -Target 'win11-x64' -Now ([datetime]'2027-01-15'))
        }

        It 'renvoie un élément par entrée de la cible' {
            $result.Count | Should -Be 3
            ($result | ForEach-Object { $_.Category }) | Should -Be @('windows-lcu', 'dotnet', 'defender-platform')
            foreach ($r in $result) { $r.Target | Should -Be 'win11-x64' }
        }

        It 'remplace {month} par le mois courant et le précédent, passage d''année compris' {
            Should -Invoke Find-OpCatalogUpdate -Scope Context -Times 1 -Exactly -ParameterFilter { $Query -eq '2027-01 Cumulative Update for Windows 11, version 25H2' }
            Should -Invoke Find-OpCatalogUpdate -Scope Context -Times 1 -Exactly -ParameterFilter { $Query -eq '2026-12 Cumulative Update for Windows 11, version 25H2' }
            Should -Invoke Find-OpCatalogUpdate -Scope Context -Times 0 -Exactly -ParameterFilter { $Query -like '2026-11*' }
        }

        It 'envoie une seule fois une recherche sans {month}' {
            Should -Invoke Find-OpCatalogUpdate -Scope Context -Times 1 -Exactly -ParameterFilter { $Query -eq 'KB4052623' }
            Should -Invoke Find-OpCatalogUpdate -Scope Context -Times 13 -Exactly
        }

        It 'journalise un avertissement pour une catégorie sans résultat' {
            Should -Invoke Write-OpLog -Scope Context -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*aucune entrée*' }
        }
    }

    Context 'Fusion des pages et des recherches' {
        It 'compte une seule fois une ligne renvoyée par deux recherches' {
            $row = Get-CatalogRow '2026-10 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5130010) (26200.9700)'
            Mock Find-OpCatalogUpdate { $row }
            $lcu = Get-OpCatalogSelection -Configuration (Get-Configuration) -Target 'win11-x64' -Now ([datetime]'2026-10-20') | Select-Object -First 1
            $lcu.Kb | Should -Be 'KB5130010'
            @($lcu.Entries).Count | Should -Be 1
        }
    }

    Context 'Windows 10' {
        BeforeAll {
            Mock Find-OpCatalogUpdate {
                if ($Query -like '*Windows 10 Version 22H2' -and $Query -like '2026-09*') {
                    Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5122878)' '2026-09-08'
                    Get-CatalogRow '2026-09 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5129236)' '2026-09-14'
                }
            }
        }

        It 'lit la page release-information de la configuration avec la build de base de l''entrée' {
            $page = Read-Fixture 'release-information.html'
            Mock Invoke-OpWebRequest { $page }
            $lcu = Get-OpCatalogSelection -Configuration (Get-Configuration) -Target 'win10-x64' -Now ([datetime]'2026-10-11') | Where-Object { $_.Category -eq 'windows-lcu' }
            $lcu.Kb | Should -Be 'KB5129236'
            $lcu.ResultingUbr | Should -Be 7727
            Should -Invoke Invoke-OpWebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://learn.microsoft.com/en-us/windows/release-health/release-information' }
        }

        It 'se replie sur le mois du titre et journalise un avertissement si la page est inaccessible' {
            Mock Invoke-OpWebRequest { throw 'HTTP 503' }
            $lcu = Get-OpCatalogSelection -Configuration (Get-Configuration) -Target 'win10-x64' -Now ([datetime]'2026-10-11') | Where-Object { $_.Category -eq 'windows-lcu' }
            $lcu.Kb | Should -Not -BeNullOrEmpty
            $lcu.ResultingUbr | Should -BeNullOrEmpty
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*release-information illisible*503*' }
        }
    }

    It 'refuse une cible absente de catalog-queries.json' {
        { Get-OpCatalogSelection -Configuration (Get-Configuration) -Target 'win7-x86' } | Should -Throw -ExpectedMessage '*win7-x86*'
    }
}
