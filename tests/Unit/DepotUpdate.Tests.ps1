# Mise à jour du dépôt, téléchargement (cahier des charges 7.1 étapes 4 à 7, 7.2) : élément du manifeste construit à
# partir de la liste, lecture de update.mum dans un .msu fabriqué avec makecab, rangement dans files/<sha256>/,
# inscription au manifeste après chaque élément, résumé des nouveautés. Aucun accès réseau : la liste, le
# téléchargement et le contrôle d'intégrité sont simulés.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($name in 'ConvertTo-OpManifestItem', 'Read-OpMsuPackage', 'Save-OpDepotFile', 'Save-OpDownload', 'Confirm-OpDownloadIntegrity',
        'Test-OpFileSignature', 'Get-OpFileVersion', 'Invoke-OpProcess', 'Get-OpDepotPlan', 'Get-OpOdtPlan', 'Save-OpOdt', 'Get-OpFreeSpace', 'Write-OpLog', 'ConvertTo-OpMaskedText',
        'Get-OpConfiguration', 'Read-OpJsonFile', 'Test-OpConfiguration', 'Get-OpPath', 'Get-OpRoot', 'Read-OpManifest', 'Test-OpManifest', 'Save-OpManifest',
        'Get-OpDepotPurgePlan') {
        . (Join-Path $module "Private\$name.ps1")
    }
    . (Join-Path $module 'Public\Invoke-OpDepotUpdate.ps1')
    . (Join-Path $module 'Public\Invoke-OpDepotPurge.ps1')
    . (Join-Path $module 'Public\Format-OpDepotPlan.ps1')

    $configuration = [pscustomobject]@{
        Settings    = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        PinnedItems = Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    function Get-PlanItem([string]$Id, [string]$Target, [string]$Category, [object[]]$Files, [hashtable]$Extra = @{}) {
        $item = [pscustomobject]@{
            Id = $Id; Target = $Target; Category = $Category; Source = 'catalog'; Kb = 'KB1'; Title = "Titre $Id"; Version = $null
            ResultingUbr = $null; BaseBuilds = @(); Prerequisites = @(); RunsAfter = @(); ReleaseDate = $null; Files = $Files; Warnings = @()
        }
        foreach ($k in $Extra.Keys) { $item.$k = $Extra[$k] }
        $item
    }
    function Get-PlanFile([string]$Name, [string]$Url = "https://h/$Name", [bool]$InDepot = $false, [string]$Failure = $null) {
        [pscustomobject]@{ FileName = $Name; Url = $Url; Sha1 = $null; SizeBytes = [long]10; Hosts = @('h'); InDepot = $InDepot; Error = $Failure }
    }
    function Get-Entry([string]$Name, [object]$Package = $null) {
        $sha = ('{0:x64}' -f [Math]::Abs($Name.GetHashCode())).PadLeft(64, '0')
        [pscustomobject]@{ path = "files/$sha/$Name"; sha256 = $sha; size = [long]10; package = $Package }
    }
}

Describe 'ConvertTo-OpManifestItem' {
    BeforeAll { Mock Write-OpLog {} }

    It 'construit une cumulative Windows 11 conforme au manifeste (cible, ordre, redémarrage, dépendances)' {
        $item = Get-PlanItem 'win11-x64-lcu-KB1' 'win11-x64' 'windows-lcu' @() @{ ResultingUbr = 9457; BaseBuilds = @(26100, 26200, 26300); Prerequisites = @('windows-checkpoint'); ReleaseDate = [datetime]'2026-09-08' }
        $m = ConvertTo-OpManifestItem -Item $item -Files @(Get-Entry 'a.msu') -Configuration $configuration
        $m.target.os | Should -Be 'win11'
        $m.target.arch | Should -Be 'x64'
        $m.target.minBuild | Should -Be 26100
        $m.target.maxBuild | Should -Be 26300
        $m.order | Should -Be 20
        $m.requiresReboot | Should -BeTrue
        $m.prerequisites | Should -Be @('windows-checkpoint')
        $m.releaseDate | Should -Be '2026-09-08'
        $m.resultingUbr | Should -Be 9457
        @(Test-OpManifest -Manifest ([pscustomobject]@{ schemaVersion = 1; items = @($m) })) | Should -BeNullOrEmpty
    }

    It 'place la plateforme Defender avant les définitions, sans redémarrage, version en texte' {
        $p = ConvertTo-OpManifestItem -Item (Get-PlanItem 'p' 'win11-arm64' 'defender-platform' @() @{ Version = [version]'4.18.26080.4' }) -Files @(Get-Entry 'p.exe') -Configuration $configuration
        $d = ConvertTo-OpManifestItem -Item (Get-PlanItem 'd' 'win11-arm64' 'defender' @() @{ Version = [version]'1.459.675.0'; RunsAfter = @('defender-platform') }) -Files @(Get-Entry 'mpam-fe.exe') -Configuration $configuration
        $p.order | Should -BeLessThan $d.order
        $d.requiresReboot | Should -BeFalse
        $d.version | Should -Be '1.459.675.0'
        $d.runsAfter | Should -Be @('defender-platform')
        $d.target.PSObject.Properties.Name | Should -Not -Contain 'minBuild'
    }

    It 'donne la plage netRelease aux fichiers .NET Windows 10 et garde le paquet lu' {
        $files = @((Get-Entry 'windows10.0-kb2-x64-ndp48_aa.msu' ([pscustomobject]@{ name = 'Package_for_DotNetRollup'; version = '10.0.4806.2' })), (Get-Entry 'windows10.0-kb3-x64-ndp481_bb.msu'))
        $m = ConvertTo-OpManifestItem -Item (Get-PlanItem 'n' 'win10-x64' 'dotnet' @()) -Files $files -Configuration $configuration
        $m.files[0].netRelease.min | Should -Be 528040
        $m.files[0].netRelease.max | Should -Be 533319
        $m.files[0].package.name | Should -Be 'Package_for_DotNetRollup'
        $m.files[1].netRelease.min | Should -Be 533320
        $m.files[1].netRelease.PSObject.Properties.Name | Should -Not -Contain 'max'
    }

    It 'contre-vérifie l''UBR d''une cumulative Windows 10 par le .msu : la valeur du .msu fait foi' {
        $item = Get-PlanItem 'w10' 'win10-x64' 'windows-lcu' @() @{ ResultingUbr = 7727; BaseBuilds = @(19045) }
        $same = ConvertTo-OpManifestItem -Item $item -Files @(Get-Entry 'w.msu' ([pscustomobject]@{ name = 'Package_for_RollupFix'; version = '19041.7727.1.0' })) -Configuration $configuration
        $same.resultingUbr | Should -Be 7727
        Should -Invoke Write-OpLog -Times 0 -Exactly -ParameterFilter { $Level -eq 'WARN' }
        $other = ConvertTo-OpManifestItem -Item $item -Files @(Get-Entry 'w.msu' ([pscustomobject]@{ name = 'Package_for_RollupFix'; version = '19041.7730.1.0' })) -Configuration $configuration
        $other.resultingUbr | Should -Be 7730
        Should -Invoke Write-OpLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*7727*7730*' }
    }

    It 'reprend les conditions d''un élément épinglé (minUbr, resultingBuild)' {
        $pinned = $configuration.PinnedItems.items[0]
        $item = Get-PlanItem $pinned.id 'win11-x64' 'windows-ekb' @() @{ Source = 'pinned'; BaseBuilds = @($pinned.appliesToBaseBuilds); RunsAfter = @('windows-lcu') }
        $m = ConvertTo-OpManifestItem -Item $item -Files @(Get-Entry 'e.msu') -Configuration $configuration
        $m.minUbr | Should -Be $pinned.minUbr
        $m.resultingBuild | Should -Be $pinned.resultingBuild
        $m.order | Should -Be 30
    }
}

Describe 'Read-OpMsuPackage (.msu fabriqué avec makecab)' {
    BeforeAll {
        # Cabinet de plusieurs fichiers, comme un vrai .msu ou son .cab : avec un seul fichier, expand.exe ignore -F et
        # décompresse le cabinet sous son propre nom. Un fichier d'accompagnement est donc toujours ajouté.
        function Write-TestCab([string]$Source, [string]$Cab) {
            $folder = Split-Path -Parent $Cab
            $extra = Join-Path $folder ([IO.Path]::GetFileNameWithoutExtension($Cab) + '-properties.txt')
            [IO.File]::WriteAllText($extra, 'accompagnement')
            $ddf = Join-Path $folder ([IO.Path]::GetFileNameWithoutExtension($Cab) + '.ddf')
            $lines = @('.OPTION EXPLICIT', ".Set CabinetNameTemplate=$([IO.Path]::GetFileName($Cab))", ".Set DiskDirectoryTemplate=$folder",
                '.Set Cabinet=on', '.Set Compress=on', '.Set InfFileName=NUL', '.Set RptFileName=NUL', "`"$Source`"", "`"$extra`"")
            [IO.File]::WriteAllLines($ddf, $lines)
            & (Join-Path $env:SystemRoot 'System32\makecab.exe') /F $ddf | Out-Null
        }
        function Write-TestMum([string]$Folder, [string]$Name, [string]$Version) {
            New-Item -ItemType Directory -Force -Path $Folder | Out-Null
            $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><assembly xmlns=`"urn:schemas-microsoft-com:asm.v3`" manifestVersion=`"1.0`"><assemblyIdentity name=`"$Name`" version=`"$Version`" processorArchitecture=`"amd64`" language=`"neutral`" /></assembly>"
            [IO.File]::WriteAllText((Join-Path $Folder 'update.mum'), $xml)
            Join-Path $Folder 'update.mum'
        }
    }

    It 'lit le nom et la version du paquet du .cab principal et nettoie le dossier de travail' {
        $dir = Join-Path $TestDrive 'msu1'
        Write-TestCab (Write-TestMum (Join-Path $dir 'mum') 'Package_for_DotNetRollup_481' '10.0.9347.1') (Join-Path $dir 'Windows11.0-KB1-x64-ndp481.cab')
        Write-TestCab (Join-Path $dir 'Windows11.0-KB1-x64-ndp481.cab') (Join-Path $dir 'test.msu')
        $work = Join-Path $dir 'work'
        $p = Read-OpMsuPackage -Path (Join-Path $dir 'test.msu') -WorkFolder $work
        $p.name | Should -Be 'Package_for_DotNetRollup_481'
        $p.version | Should -Be '10.0.9347.1'
        Test-Path -LiteralPath $work | Should -BeFalse
    }

    It 'ignore le SSU embarqué (SSU-*.cab)' {
        $dir = Join-Path $TestDrive 'msu2'
        Write-TestCab (Write-TestMum (Join-Path $dir 'ssu') 'Package_for_ServicingStack_7714' '19041.7714.1.3') (Join-Path $dir 'SSU-19041.7714-x64.cab')
        $msu = Join-Path $dir 'ssu-seul.msu'
        Write-TestCab (Join-Path $dir 'SSU-19041.7714-x64.cab') $msu
        Read-OpMsuPackage -Path $msu -WorkFolder (Join-Path $dir 'work') | Should -BeNullOrEmpty
    }

    It 'renvoie $null pour un .msu sans update.mum lisible' {
        $dir = Join-Path $TestDrive 'msu3'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'autre.txt'), 'rien')
        Write-TestCab (Join-Path $dir 'autre.txt') (Join-Path $dir 'vide.msu')
        Read-OpMsuPackage -Path (Join-Path $dir 'vide.msu') -WorkFolder (Join-Path $dir 'work') | Should -BeNullOrEmpty
    }
}

Describe 'Save-OpDepotFile' {
    BeforeAll {
        Mock Write-OpLog {}
        Mock Save-OpDownload {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
            [IO.File]::WriteAllText($Destination, 'contenu')
            [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $false; SizeBytes = 7 }
        }
        Mock Confirm-OpDownloadIntegrity { [pscustomobject]@{ Path = $Path; Sha256 = ('c' * 64); Sha1 = ('d' * 40); Signer = 'O=Microsoft Corporation'; RootThumbprint = 'x' } }
        Mock Read-OpMsuPackage { [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.9347.1' } }
    }

    It 'range le fichier dans files, dossier du SHA-256, sous son nom d''origine, et vide le dossier temporaire' {
        $tool = Join-Path $TestDrive 'outil1'
        $entry = Save-OpDepotFile -Item (Get-PlanItem 'n' 'win11-x64' 'dotnet' @()) -File (Get-PlanFile 'n.msu') -Configuration $configuration -Root $tool
        $entry.path | Should -Be "files/$('c' * 64)/n.msu"
        $entry.size | Should -Be 7
        $entry.package.version | Should -Be '10.0.9347.1'
        Test-Path -LiteralPath (Join-Path $tool "depot\files\$('c' * 64)\n.msu") | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $tool 'depot\.tmp') -Recurse -File).Count | Should -Be 0
    }

    It 'sépare dans le dossier temporaire deux fichiers de même nom servis par deux liens' {
        $tool = Join-Path $TestDrive 'outil2'
        $destinations = New-Object System.Collections.Generic.List[string]
        Mock Save-OpDownload { $destinations.Add($Destination); New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null; [IO.File]::WriteAllText($Destination, 'x') }
        Mock Get-OpFileVersion { [version]'1.459.675.0' }
        foreach ($a in 'amd64', 'arm64') {
            $null = Save-OpDepotFile -Item (Get-PlanItem 'd' 'win11-x64' 'defender' @() @{ Version = [version]'1.459.675.0' }) -File (Get-PlanFile 'mpam-fe.exe' "https://h/mpam-fe.exe?arch=$a") -Configuration $configuration -Root $tool
        }
        $destinations.Count | Should -Be 2
        $destinations[0] | Should -Not -Be $destinations[1]
    }

    It 'refuse et supprime un fichier Defender dont la version diffère de celle annoncée' {
        $tool = Join-Path $TestDrive 'outil3'
        Mock Get-OpFileVersion { [version]'1.459.600.0' }
        { Save-OpDepotFile -Item (Get-PlanItem 'd' 'win11-x64' 'defender' @() @{ Version = [version]'1.459.675.0' }) -File (Get-PlanFile 'mpam-fe.exe') -Configuration $configuration -Root $tool } |
            Should -Throw '*version 1.459.600.0, 1.459.675.0 annoncée*'
        @(Get-ChildItem -LiteralPath (Join-Path $tool 'depot') -Recurse -File -Filter 'mpam-fe.exe').Count | Should -Be 0
    }

    It 'respecte -WhatIf : rien téléchargé' {
        $null = Save-OpDepotFile -Item (Get-PlanItem 'n' 'win11-x64' 'dotnet' @()) -File (Get-PlanFile 'n.msu') -Configuration $configuration -Root (Join-Path $TestDrive 'outil4') -WhatIf
        Should -Invoke Save-OpDownload -Times 0 -Exactly
    }
}

Describe 'Invoke-OpDepotUpdate (téléchargement)' {
    BeforeAll {
        Mock Write-OpLog {}
        Mock Get-OpOdtPlan {} # ODT : Odt.Tests.ps1
        Mock Get-OpFreeSpace { [long]1000000 }
        function Initialize-TestTool([string]$Name) {
            $tool = Join-Path $TestDrive $Name
            New-Item -ItemType Directory -Force -Path $tool | Out-Null
            Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
            Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
            $tool
        }
        function Get-Manifest([string]$Tool) { Get-Content -Path (Join-Path $Tool 'depot\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
        $script:plan = {
            Get-PlanItem 'win11-x64-lcu-KB1' 'win11-x64' 'windows-lcu' @((Get-PlanFile 'lcu.msu')) @{ ResultingUbr = 9457; BaseBuilds = @(26100); Prerequisites = @('windows-checkpoint') }
            Get-PlanItem 'win11-x64-checkpoint-KB2' 'win11-x64' 'windows-checkpoint' @((Get-PlanFile 'cp.msu'))
            Get-PlanItem 'win11-arm64-checkpoint-KB2' 'win11-arm64' 'windows-checkpoint' @((Get-PlanFile 'cp.msu'))
            Get-PlanItem 'win11-x64-dotnet-KB3' 'win11-x64' 'dotnet' @((Get-PlanFile 'refuse.msu' 'https://h/refuse.msu' $false 'Hôte non autorisé'))
        }
    }

    It 'télécharge une fois un fichier partagé, inscrit les éléments complets et résume les nouveautés' {
        $tool = Initialize-TestTool 'd1'
        Mock Get-OpDepotPlan $script:plan
        Mock Save-OpDepotFile { Get-Entry $File.FileName }
        $r = Invoke-OpDepotUpdate -Root $tool
        Should -Invoke Save-OpDepotFile -Times 2 -Exactly
        @($r.NewItems | ForEach-Object { $_.id }) | Should -Be @('win11-x64-lcu-KB1', 'win11-x64-checkpoint-KB2', 'win11-arm64-checkpoint-KB2')
        $r.ErrorCount | Should -Be 2
        $m = Get-Manifest $tool
        @($m.items).Count | Should -Be 3
        @(Test-OpManifest -Manifest $m) | Should -BeNullOrEmpty
        $text = (Format-OpDepotPlan -Result $r) -join "`n"
        $text | Should -Match 'Nouveautés inscrites au manifeste : 3'
        $text | Should -Match '\+ win11-x64-lcu-KB1 : windows-lcu \(KB1, UBR 9457\)'
        $text | Should -Match '2 erreur\(s\)'
        # Purge en fin de mise à jour : rien à retirer, et les fichiers simulés (absents du disque) ne sont pas orphelins.
        @($r.Purge.RemovedItems).Count | Should -Be 0
        $text | Should -Match 'Purge : rien à retirer'
    }

    It 'reprend les entrées déjà au manifeste et ne compte pas comme nouveauté un élément déjà inscrit' {
        $tool = Initialize-TestTool 'd2'
        Mock Get-OpDepotPlan $script:plan
        Mock Save-OpDepotFile { Get-Entry $File.FileName }
        $null = Invoke-OpDepotUpdate -Root $tool
        Mock Get-OpDepotPlan {
            Get-PlanItem 'win11-x64-lcu-KB1' 'win11-x64' 'windows-lcu' @((Get-PlanFile 'lcu.msu' 'https://h/lcu.msu' $true)) @{ ResultingUbr = 9457; BaseBuilds = @(26100) }
            Get-PlanItem 'win10-x64-checkpoint-KB2' 'win10-x64' 'windows-checkpoint' @((Get-PlanFile 'cp.msu' 'https://h/cp.msu' $true))
        }
        $r = Invoke-OpDepotUpdate -Root $tool
        Should -Invoke Save-OpDepotFile -Times 2 -Exactly
        @($r.NewItems | ForEach-Object { $_.id }) | Should -Be @('win10-x64-checkpoint-KB2')
        (@((Get-Manifest $tool).items) | Where-Object { $_.id -eq 'win10-x64-checkpoint-KB2' }).files[0].path | Should -Be (Get-Entry 'cp.msu').path
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Not -Match 'erreur'
    }

    It 'n''inscrit pas un élément dont le téléchargement échoue, et continue' {
        $tool = Initialize-TestTool 'd3'
        Mock Get-OpDepotPlan $script:plan
        Mock Save-OpDepotFile { if ($File.FileName -eq 'lcu.msu') { throw 'Fichier refusé, lcu.msu : SHA-1 faux.' }; Get-Entry $File.FileName }
        $r = Invoke-OpDepotUpdate -Root $tool
        @($r.NewItems | ForEach-Object { $_.id }) | Should -Not -Contain 'win11-x64-lcu-KB1'
        $r.ErrorCount | Should -Be 3
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*win11-x64-lcu-KB1 : élément non inscrit*SHA-1 faux*' }
    }

    It 's''arrête avant tout téléchargement quand l''espace manque' {
        $tool = Initialize-TestTool 'd4'
        Mock Get-OpDepotPlan $script:plan
        Mock Get-OpFreeSpace { [long]5 }
        Mock Save-OpDepotFile {}
        { Invoke-OpDepotUpdate -Root $tool } | Should -Throw '*avant tout téléchargement*espace insuffisant*'
        Should -Invoke Save-OpDepotFile -Times 0 -Exactly
    }

    It 'respecte -WhatIf : ni téléchargement ni manifeste' {
        $tool = Initialize-TestTool 'd5'
        Mock Get-OpDepotPlan $script:plan
        Mock Save-OpDepotFile {}
        $null = Invoke-OpDepotUpdate -Root $tool -WhatIf
        Should -Invoke Save-OpDepotFile -Times 0 -Exactly
        Test-Path -Path (Join-Path $tool 'depot\manifest.json') | Should -BeFalse
    }

    It 'annonce un dépôt déjà à jour' {
        $r = [pscustomobject]@{ ListOnly = $false; Items = @(); DownloadBytes = 0; DownloadCount = 0; UnknownSizeCount = 0; FreeBytes = $null; EnoughSpace = $null; ErrorCount = 0; NewItems = @() }
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'Aucune nouveauté'
    }
}
