# Liste de la mise à jour du dépôt (-ListOnly, cahier des charges 7.1) : fichiers des entrées retenues, prérequis joints
# (R-02), fileNamePattern, éléments épinglés, état « au dépôt », liens refusés, espace libre, mise en forme.
# Aucun accès réseau : la sélection, la fenêtre de téléchargement et la résolution des liens sont simulées ; la fenêtre
# de KB5129195 est la page réelle enregistrée (tests/Fixtures/catalog).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    # Comme dans le module (OffPatch.psm1) : un accès hors limites ou à une propriété absente doit échouer ici aussi.
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($name in 'ConvertFrom-OpCatalogDownloadDialog', 'Get-OpCatalogDownloadLink', 'Invoke-OpWebRequest', 'Get-OpCatalogSelection', 'Resolve-OpDownloadUrl',
        'Get-OpDepotPlan', 'Get-OpDefenderDefinitionPlan', 'Get-OpOdtPlan', 'Get-OpFileVersion', 'Get-OpFreeSpace', 'Write-OpLog', 'ConvertTo-OpMaskedText', 'Get-OpConfiguration', 'Read-OpJsonFile',
        'Test-OpConfiguration', 'Get-OpPath', 'Get-OpRoot', 'Read-OpManifest', 'Test-OpManifest') {
        . (Join-Path $module "Private\$name.ps1")
    }
    . (Join-Path $module 'Public\Invoke-OpDepotUpdate.ps1')
    . (Join-Path $module 'Public\Format-OpDepotPlan.ps1')
    $dialog = [System.IO.File]::ReadAllText((Join-Path $root 'tests\Fixtures\catalog\dialog-kb5129195.html'))

    function Get-Configuration([string[]]$Targets, [bool]$Enablement = $true) {
        $c = [pscustomobject]@{
            Settings       = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            CatalogQueries = Get-Content -Path (Join-Path $root 'config\catalog-queries.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            PinnedItems    = Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        $c.Settings.targets = $Targets
        $c.Settings.windows.includeEnablementPackage = $Enablement
        $c
    }
    function Get-Selection([string]$Category, [string]$Kb, [string]$Pick = 'highestUbr', [object]$Version = $null, [string]$Pattern = $null, [string[]]$Prerequisites = @()) {
        [pscustomobject]@{
            Category = $Category; Pick = $Pick; Kb = $Kb; UpdateId = '11111111-2222-3333-4444-555555555555'; Title = "Titre $Kb"
            Entries = @(); BaseBuilds = @(26100); ResultingUbr = 9457; Version = $Version; Month = '2026-09'; ReleaseDate = $null
            SizeBytes = 1; FileNamePattern = $Pattern; Prerequisites = $Prerequisites; RunsAfter = @(); Warnings = @()
        }
    }
    function Get-Link([string]$Name) {
        [pscustomobject]@{ Url = "https://catalog.s.download.windowsupdate.com/d/$Name"; FileName = $Name; Sha1 = ('a' * 40) }
    }
    $emptyManifest = [pscustomobject]@{ schemaVersion = 1; items = @() }
}

Describe 'Get-OpDepotPlan' {
    BeforeAll {
        Mock Write-OpLog {}
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = $Url; Hosts = @(([uri]$Url).Host); SizeBytes = [int64]1000 } }
        # Définitions Defender : testées à part (Describe Get-OpDefenderDefinitionPlan).
        Mock Get-OpDefenderDefinitionPlan {}
    }

    It 'ajoute les définitions Defender de chaque cible' {
        Mock Get-OpCatalogSelection {}
        Mock Get-OpDefenderDefinitionPlan { [pscustomobject]@{ Id = "$Target-defender"; Category = 'defender' } }
        $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-x64', 'win11-arm64') $false) -Manifest $emptyManifest)
        ($plan | ForEach-Object { $_.Id }) | Should -Be @('win11-x64-defender', 'win11-arm64-defender')
    }

    Context 'Cumulative Windows 11 et sa checkpoint jointe (fenêtre réelle de KB5129195)' {
        BeforeAll {
            Mock Get-OpCatalogSelection { Get-Selection -Category 'windows-lcu' -Kb 'KB5129195' -Prerequisites @('windows-checkpoint') }
            Mock Invoke-OpWebRequest { $dialog }
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-x64') $false) -Manifest $emptyManifest)
            $lcu = $plan | Where-Object { $_.Category -eq 'windows-lcu' }
            $checkpoint = $plan | Where-Object { $_.Category -eq 'windows-checkpoint' }
        }

        It 'garde le fichier du KB retenu dans l''élément de la cumulative' {
            $lcu.Id | Should -Be 'win11-x64-lcu-KB5129195'
            @($lcu.Files).Count | Should -Be 1
            $lcu.Files[0].FileName | Should -Match '^windows11\.0-kb5129195-x64_[0-9a-f]{40}\.msu$'
            $lcu.Prerequisites | Should -Be @('windows-checkpoint')
            $lcu.ResultingUbr | Should -Be 9457
        }

        It 'fait de l''autre fichier un élément windows-checkpoint, sans numéro en dur' {
            $checkpoint.Id | Should -Be 'win11-x64-checkpoint-KB5043080'
            $checkpoint.Kb | Should -Be 'KB5043080'
            $checkpoint.Files[0].FileName | Should -Match '^windows11\.0-kb5043080-x64_'
        }

        It 'résout chaque lien et relève la taille annoncée' {
            foreach ($f in @($lcu.Files) + @($checkpoint.Files)) {
                $f.InDepot | Should -BeFalse
                $f.SizeBytes | Should -Be 1000
                $f.Hosts | Should -Be @('catalog.sf.dl.delivery.mp.microsoft.com')
            }
        }

        It 'n''ajoute pas l''enablement package quand l''option est désactivée' {
            @($plan | Where-Object { $_.Category -eq 'windows-ekb' }).Count | Should -Be 0
        }
    }

    Context 'Choix du fichier et entrées à plusieurs fichiers' {
        It 'garde seulement le fichier qui correspond à fileNamePattern et nomme l''élément par sa version' {
            Mock Get-OpCatalogSelection { Get-Selection -Category 'defender-platform' -Kb 'KB4052623' -Pick 'highestVersion' -Version ([version]'4.18.26080.4') -Pattern '^updateplatform\.arm64fre_[0-9a-f]{40}\.exe$' }
            Mock Get-OpCatalogDownloadLink { Get-Link "updateplatform.amd64fre_$('1' * 40).exe"; Get-Link "updateplatform.x86fre_$('2' * 40).exe"; Get-Link "updateplatform.arm64fre_$('3' * 40).exe" }
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-arm64') $false) -Manifest $emptyManifest)
            $plan.Count | Should -Be 1
            $plan[0].Id | Should -Be 'win11-arm64-defender-platform-4.18.26080.4'
            @($plan[0].Files).Count | Should -Be 1
            $plan[0].Files[0].FileName | Should -Match '^updateplatform\.arm64fre_'
        }

        It 'garde les deux fichiers .NET Windows 10 dans le même élément quand aucun ne porte le KB de l''entrée' {
            Mock Get-OpCatalogSelection { Get-Selection -Category 'dotnet' -Kb 'KB5126146' -Pick 'latestMonth' }
            Mock Get-OpCatalogDownloadLink { Get-Link "windows10.0-kb5126046-x64-ndp48_$('4' * 40).msu"; Get-Link "windows10.0-kb5126421-x64-ndp481_$('5' * 40).msu" }
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win10-x64')) -Manifest $emptyManifest | Where-Object { $_.Source -eq 'catalog' })
            $plan.Count | Should -Be 1
            @($plan[0].Files).Count | Should -Be 2
        }

        It 'ignore une catégorie sans élément retenu' {
            Mock Get-OpCatalogSelection { Get-Selection -Category 'dotnet' -Kb $null }
            Mock Get-OpCatalogDownloadLink { throw 'ne doit pas être appelé' }
            @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-x64') $false) -Manifest $emptyManifest).Count | Should -Be 0
        }
    }

    Context 'Éléments épinglés' {
        BeforeAll { Mock Get-OpCatalogSelection {} }

        It 'ajoute l''enablement package de chaque cible Windows 11 quand l''option est active' {
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-x64', 'win11-arm64')) -Manifest $emptyManifest)
            ($plan | ForEach-Object { $_.Id }) | Should -Be @('win11-x64-ekb-26H2', 'win11-arm64-ekb-26H2')
            $plan[0].Source | Should -Be 'pinned'
            $plan[0].RunsAfter | Should -Be @('windows-lcu')
            $plan[0].Files[0].FileName | Should -Match '^Windows11\.0-KB5121794-x64_'
        }

        It 'ajoute le SSU autonome à la cible Windows 10 seulement' {
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win10-x64')) -Manifest $emptyManifest)
            ($plan | ForEach-Object { $_.Category }) | Should -Be @('windows-ssu')
        }
    }

    Context 'Fichier déjà au dépôt et lien refusé' {
        It 'marque « au dépôt » un fichier du même nom dans le manifeste, sans requête HEAD' {
            Mock Get-OpCatalogSelection {}
            $name = ([uri](Get-Configuration @('win10-x64')).PinnedItems.items[2].url).Segments[-1]
            $manifest = [pscustomobject]@{ schemaVersion = 1; items = @([pscustomobject]@{ id = 'x'; files = @([pscustomobject]@{ path = "files/$('0' * 64)/$name" }) }) }
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win10-x64')) -Manifest $manifest)
            $plan[0].Files[0].InDepot | Should -BeTrue
            Should -Invoke Resolve-OpDownloadUrl -Times 0 -Exactly
        }

        It 'porte l''erreur sur le fichier refusé sans arrêter la liste' {
            Mock Get-OpCatalogSelection {}
            Mock Resolve-OpDownloadUrl { throw 'Hôte non autorisé : exemple.net.' }
            $plan = @(Get-OpDepotPlan -Configuration (Get-Configuration @('win11-x64', 'win11-arm64')) -Manifest $emptyManifest)
            $plan.Count | Should -Be 2
            foreach ($p in $plan) { $p.Files[0].Error | Should -BeLike '*Hôte non autorisé*' }
        }
    }
}

Describe 'Get-OpDefenderDefinitionPlan' {
    BeforeAll {
        Mock Write-OpLog {}
        # Forme de l'URL finale relevée en R-06.
        function Get-FinalUrl([string]$Arch, [string]$Version = '1.459.553.0') {
            "https://definitionupdates.microsoft.com/packages/content/mpam-fe.exe?packageType=Signatures&packageVersion=$Version&arch=$Arch&engineVersion=1.1.26080.3"
        }
    }

    It 'résout le lien de l''architecture et lit la version dans l''URL finale' {
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = (Get-FinalUrl 'arm64'); Hosts = @('go.microsoft.com', 'definitionupdates.microsoft.com'); SizeBytes = [int64]222341064 } }
        $c = Get-Configuration @('win11-arm64')
        $item = Get-OpDefenderDefinitionPlan -Configuration $c -Manifest $emptyManifest -Target 'win11-arm64'
        $item.Id | Should -Be 'win11-arm64-defender-1.459.553.0'
        $item.Category | Should -Be 'defender'
        $item.Version | Should -Be ([version]'1.459.553.0')
        $item.RunsAfter | Should -Be @('defender-platform')
        $item.Files[0].FileName | Should -Be 'mpam-fe.exe'
        $item.Files[0].SizeBytes | Should -Be 222341064
        $item.Files[0].InDepot | Should -BeFalse
        $item.Files[0].Error | Should -BeNullOrEmpty
        Should -Invoke Resolve-OpDownloadUrl -Times 1 -Exactly -ParameterFilter { $Url -eq $c.Settings.downloadPages.defenderDefinitions.arm64 }
    }

    It 'reconnaît une version déjà au dépôt pour la même architecture seulement' {
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = (Get-FinalUrl 'amd64'); Hosts = @('definitionupdates.microsoft.com'); SizeBytes = [int64]1 } }
        $manifest = [pscustomobject]@{ schemaVersion = 1; items = @(
                [pscustomobject]@{ id = 'a'; category = 'defender'; version = '1.459.553.0'; target = [pscustomobject]@{ os = 'win11'; arch = 'arm64' } }
                [pscustomobject]@{ id = 'b'; category = 'defender'; version = '1.459.400.0'; target = [pscustomobject]@{ os = 'win11'; arch = 'x64' } }
            ) }
        (Get-OpDefenderDefinitionPlan -Configuration (Get-Configuration @('win11-x64')) -Manifest $manifest -Target 'win11-x64').Files[0].InDepot | Should -BeFalse
        $manifest.items[1].version = '1.459.553.0'
        (Get-OpDefenderDefinitionPlan -Configuration (Get-Configuration @('win11-x64')) -Manifest $manifest -Target 'win11-x64').Files[0].InDepot | Should -BeTrue
    }

    It 'porte l''erreur quand le lien est refusé' {
        Mock Resolve-OpDownloadUrl { throw 'Hôte non autorisé : exemple.net.' }
        $item = Get-OpDefenderDefinitionPlan -Configuration (Get-Configuration @('win10-x64')) -Manifest $emptyManifest -Target 'win10-x64'
        $item.Id | Should -Be 'win10-x64-defender'
        $item.Files[0].Error | Should -BeLike '*Hôte non autorisé*'
    }

    It 'porte l''erreur quand l''URL finale ne donne pas la version' {
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = 'https://definitionupdates.microsoft.com/packages/content/mpam-fe.exe?arch=amd64'; Hosts = @(); SizeBytes = $null } }
        (Get-OpDefenderDefinitionPlan -Configuration (Get-Configuration @('win11-x64')) -Manifest $emptyManifest -Target 'win11-x64').Files[0].Error |
            Should -BeLike 'Version des définitions absente*'
    }

    It 'porte l''erreur quand l''URL finale désigne une autre architecture' {
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = (Get-FinalUrl 'amd64'); Hosts = @(); SizeBytes = $null } }
        (Get-OpDefenderDefinitionPlan -Configuration (Get-Configuration @('win11-arm64')) -Manifest $emptyManifest -Target 'win11-arm64').Files[0].Error |
            Should -BeLike '*architecture arm64*'
    }
}

Describe 'Get-OpFileVersion' {
    It 'lit la version d''un exécutable du système' {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $v = Get-OpFileVersion -Path $exe
        $v | Should -BeOfType [version]
        $v.Major | Should -Be (Get-Item -LiteralPath $exe).VersionInfo.FileMajorPart
    }

    It 'renvoie $null pour un fichier sans version' {
        $file = Join-Path $TestDrive 'sans-version.exe'
        [System.IO.File]::WriteAllBytes($file, [byte[]](1..16))
        Get-OpFileVersion -Path $file | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-OpDepotUpdate' {
    BeforeAll {
        Mock Write-OpLog {}
        Mock Get-OpOdtPlan {} # ODT : Odt.Tests.ps1
        $tool = Join-Path $TestDrive 'outil'
        New-Item -ItemType Directory -Force -Path $tool | Out-Null
        Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
        function Get-PlanFile([string]$Name, [object]$Size, [bool]$InDepot = $false, [string]$Failure = $null, [string]$Url = "https://h/$Name") {
            [pscustomobject]@{ FileName = $Name; Url = $Url; Sha1 = $null; SizeBytes = $Size; Hosts = @('h'); InDepot = $InDepot; Error = $Failure }
        }
        function Get-PlanItem([string]$Id, [object[]]$Files) {
            [pscustomobject]@{ Id = $Id; Target = 'win11-x64'; Category = 'windows-lcu'; Kb = 'KB1'; ResultingUbr = 1; Version = $null; Files = $Files; Warnings = @() }
        }
    }

    Context 'Résumé' {
        BeforeAll {
            Mock Get-OpDepotPlan {
                Get-PlanItem 'a' @((Get-PlanFile 'lcu-x64.msu' 3000), (Get-PlanFile 'checkpoint.msu' 500))
                Get-PlanItem 'b' @((Get-PlanFile 'checkpoint.msu' 500), (Get-PlanFile 'ancien.msu' 9999 $true))
                Get-PlanItem 'c' @((Get-PlanFile 'inconnu.msu' $null), (Get-PlanFile 'refuse.msu' 10 $false 'Hôte non autorisé'))
            }
        }

        It 'compte une fois un fichier partagé, ignore les fichiers au dépôt et compte les refus' {
            Mock Get-OpFreeSpace { [long]1000000 }
            $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
            $r.DownloadCount | Should -Be 3
            $r.DownloadBytes | Should -Be 3500
            $r.UnknownSizeCount | Should -Be 1
            $r.ErrorCount | Should -Be 1
            $r.EnoughSpace | Should -BeTrue
            @($r.Items).Count | Should -Be 3
        }

        It 'compte deux fois un même nom servi par deux liens (mpam-fe.exe x64 et ARM64)' {
            Mock Get-OpFreeSpace { [long]1000000 }
            Mock Get-OpDepotPlan {
                Get-PlanItem 'x64' @(Get-PlanFile 'mpam-fe.exe' 200 $false $null 'https://h/mpam-fe.exe?arch=amd64')
                Get-PlanItem 'arm64' @(Get-PlanFile 'mpam-fe.exe' 300 $false $null 'https://h/mpam-fe.exe?arch=arm64')
                Get-PlanItem 'x64-bis' @(Get-PlanFile 'mpam-fe.exe' 200 $false $null 'https://h/mpam-fe.exe?arch=amd64')
            }
            $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
            $r.DownloadCount | Should -Be 2
            $r.DownloadBytes | Should -Be 500
        }

        It 'signale un espace insuffisant' {
            Mock Get-OpFreeSpace { [long]100 }
            $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
            $r.EnoughSpace | Should -BeFalse
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*espace insuffisant*' }
        }

        It 'lit le manifeste du dépôt de la racine donnée, sans rien y écrire' {
            Mock Get-OpFreeSpace { $null }
            $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
            $r.EnoughSpace | Should -BeNullOrEmpty
            Test-Path -Path (Join-Path $tool 'depot') | Should -BeFalse
        }
    }

    It 'journalise puis relance une erreur du catalogue' {
        Mock Get-OpDepotPlan { throw 'Page du catalogue non reconnue' }
        { Invoke-OpDepotUpdate -ListOnly -Root $tool } | Should -Throw -ExpectedMessage '*non reconnue*'
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*interrompue*' }
    }
}

Describe 'Get-OpFreeSpace' {
    It 'lit l''espace libre du volume d''un chemin qui n''existe pas encore' {
        Get-OpFreeSpace -Path (Join-Path $TestDrive 'depot\absent') | Should -BeGreaterThan 0
    }

    It 'renvoie $null pour un chemin réseau' {
        Get-OpFreeSpace -Path '\\serveur\partage\depot' | Should -BeNullOrEmpty
    }
}

Describe 'Format-OpDepotPlan' {
    It 'donne l''état de chaque fichier, les tailles en français et le manque d''espace' {
        $result = [pscustomobject]@{
            Items            = @([pscustomobject]@{
                    Id = 'a'; Target = 'win11-x64'; Category = 'windows-lcu'; Kb = 'KB1'; ResultingUbr = 9457; Version = $null; Warnings = @('à vérifier')
                    Files = @(
                        [pscustomobject]@{ FileName = 'nouveau.msu'; SizeBytes = [long](4.5 * 1GB); InDepot = $false; Error = $null }
                        [pscustomobject]@{ FileName = 'ancien.msu'; SizeBytes = $null; InDepot = $true; Error = $null }
                        [pscustomobject]@{ FileName = 'refuse.msu'; SizeBytes = $null; InDepot = $false; Error = 'Hôte non autorisé' }
                    )
                })
            DownloadBytes    = [long](4.5 * 1GB)
            DownloadCount    = 1
            UnknownSizeCount = 0
            FreeBytes        = [long](1.5 * 1GB)
            EnoughSpace      = $false
            ErrorCount       = 1
        }
        $text = (Format-OpDepotPlan -Result $result) -join "`n"
        $text | Should -Match 'Cible win11-x64'
        $text | Should -Match '\[à télécharger\] windows-lcu \(KB1, UBR 9457\) : nouveau\.msu, 4,50 Go'
        $text | Should -Match '\[au dépôt\] windows-lcu \(KB1, UBR 9457\) : ancien\.msu'
        $text | Should -Match '\[REFUSÉ\] .*refuse\.msu'
        $text | Should -Match 'Avertissement : à vérifier'
        $text | Should -Match 'il manque 3,00 Go'
        $text | Should -Match 'Aucun fichier téléchargé'
    }

    It 'affiche la version des définitions Defender, élément sans KB' {
        $result = [pscustomobject]@{
            Items = @([pscustomobject]@{
                    Id = 'win11-x64-defender-1.459.553.0'; Target = 'win11-x64'; Category = 'defender'; Kb = $null; ResultingUbr = $null; Version = [version]'1.459.553.0'; Warnings = @()
                    Files = @([pscustomobject]@{ FileName = 'mpam-fe.exe'; SizeBytes = [long]222853576; InDepot = $false; Error = $null })
                })
            DownloadBytes = [long]222853576; DownloadCount = 1; UnknownSizeCount = 0; FreeBytes = $null; EnoughSpace = $null; ErrorCount = 0
        }
        (Format-OpDepotPlan -Result $result) -join "`n" | Should -Match '\[à télécharger\] defender \(version 1\.459\.553\.0\) : mpam-fe\.exe, 212,5 Mo'
    }
}
