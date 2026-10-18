# Détection par catégorie (cahier des charges 8.3) sur un manifeste, un relevé du PC, une liste DISM et un état
# Defender simulés. Rien n'est lu sur le PC réel.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }

    $tool = Join-Path $TestDrive 'outil'
    New-Item -ItemType Directory -Force -Path $tool | Out-Null
    Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
    Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool

    # Élément du manifeste dont les fichiers existent au dépôt (sauf -Absent).
    function ConvertTo-TestItem([string]$Id, [string]$Category, [string]$Target, [hashtable]$Fields, [object[]]$Files, [switch]$Absent) {
        $os, $arch = $Target -split '-', 2
        $item = [ordered]@{ id = $Id; category = $Category; target = [pscustomobject]@{ os = $os; arch = $arch }; prerequisites = @(); runsAfter = @() }
        if ($Fields) { foreach ($k in $Fields.Keys) { $item[$k] = $Fields[$k] } }
        if (-not $Files) { $Files = @([pscustomobject]@{ path = "files/$Id/$Id.msu" }) }
        $item.files = @($Files)
        if (-not $Absent) {
            foreach ($f in $Files) {
                $p = Join-Path $tool ('depot\' + ($f.path -replace '/', '\'))
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
                Set-Content -LiteralPath $p -Value 'x' -Encoding ASCII
            }
        }
        [pscustomobject]$item
    }
    function Initialize-TestInfo([string]$Target = 'win11-x64', [int]$Build = 26200, [int]$Ubr = 9457) {
        $script:info = [pscustomobject]@{ Target = $Target; CurrentBuild = $Build; Ubr = $Ubr; Office = $null }
    }
    function Get-TestState([object[]]$Items) {
        $script:testItems = @($Items)
        Mock Read-OpManifest { [pscustomobject]@{ schemaVersion = 1; generatedAt = '2026-10-14T00:00:00Z'; items = $script:testItems } }
        @(Get-OpUpdateState -Root $tool -SystemInfo $script:info)
    }
    function Get-StateOf([object[]]$States, [string]$Id) { $States | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

    $lcuFields = @{ baseBuilds = @(26100, 26200, 26300); prerequisites = @('windows-checkpoint') }
}

Describe 'Get-OpUpdateState : cumulatives Windows, checkpoint, SSU, enablement package' {
    BeforeEach {
        Initialize-TestInfo
        Mock Get-WindowsPackage { }
        Mock Get-MpComputerStatus { throw 'non simulé' }
    }

    It 'seule la cumulative la plus récente est à installer ; l''ancienne déjà couverte est à jour, la checkpoint aussi' {
        $s = Get-TestState @(
            ConvertTo-TestItem 'w-lcu-KB2' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9550; releaseDate = '2026-10-13' })
            ConvertTo-TestItem 'w-lcu-KB1' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9457; releaseDate = '2026-09-08' })
            ConvertTo-TestItem 'w-cp-KB0' 'windows-checkpoint' 'win11-x64' @{ resultingUbr = 1742 }
        )
        (Get-StateOf $s 'w-lcu-KB2').State | Should -Be 'Pending'
        (Get-StateOf $s 'w-lcu-KB2').Available | Should -Be '26200.9550'
        (Get-StateOf $s 'w-lcu-KB1').State | Should -Be 'UpToDate'
        (Get-StateOf $s 'w-cp-KB0').State | Should -Be 'UpToDate'
    }

    It 'cumulative ancienne non couverte : repli, non applicable ; build hors baseBuilds : non applicable' {
        Initialize-TestInfo -Build 26100 -Ubr 1000
        $s = Get-TestState @(
            ConvertTo-TestItem 'w-lcu-KB2' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9550 })
            ConvertTo-TestItem 'w-lcu-KB1' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9457 })
            ConvertTo-TestItem 'w-cp-KB0' 'windows-checkpoint' 'win11-x64' @{ resultingUbr = 1742 }
        )
        (Get-StateOf $s 'w-lcu-KB1').State | Should -Be 'NotApplicable'
        (Get-StateOf $s 'w-lcu-KB1').Reason | Should -BeLike '*Repli*w-lcu-KB2*'
        (Get-StateOf $s 'w-cp-KB0').State | Should -Be 'Pending'
        Initialize-TestInfo -Build 22631 -Ubr 5000
        $s = Get-TestState @(ConvertTo-TestItem 'w-lcu-KB2' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9550 }))
        (Get-StateOf $s 'w-lcu-KB2').State | Should -Be 'NotApplicable'
    }

    It 'checkpoint sans UBR connu : erreur' {
        $s = Get-TestState @(
            ConvertTo-TestItem 'w-lcu-KB2' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9550 })
            ConvertTo-TestItem 'w-cp-KB0' 'windows-checkpoint' 'win11-x64'
        )
        (Get-StateOf $s 'w-cp-KB0').State | Should -Be 'Error'
        (Get-StateOf $s 'w-cp-KB0').Reason | Should -BeLike '*checkpointUbr*'
    }

    It 'SSU Windows 10 : à installer sous applyBelowUbr, non applicable au-dessus' {
        Initialize-TestInfo -Target 'win10-x64' -Build 19045 -Ubr 3000
        $ssu = ConvertTo-TestItem 'w10-ssu' 'windows-ssu' 'win10-x64' @{ baseBuilds = @(19045); applyBelowUbr = 3271 }
        (Get-StateOf (Get-TestState @($ssu)) 'w10-ssu').State | Should -Be 'Pending'
        Initialize-TestInfo -Target 'win10-x64' -Build 19045 -Ubr 7727
        (Get-StateOf (Get-TestState @($ssu)) 'w10-ssu').State | Should -Be 'NotApplicable'
    }

    It 'enablement package : à installer depuis 26200, non applicable en 26300 ou si l''option est désactivée' {
        $ekb = ConvertTo-TestItem 'w-ekb' 'windows-ekb' 'win11-x64' @{ baseBuilds = @(26100, 26200); minUbr = 9550; resultingBuild = 26300 }
        (Get-StateOf (Get-TestState @($ekb)) 'w-ekb').State | Should -Be 'Pending'
        Initialize-TestInfo -Build 26300 -Ubr 9550
        (Get-StateOf (Get-TestState @($ekb)) 'w-ekb').State | Should -Be 'NotApplicable'
        Initialize-TestInfo
        Mock Get-OpConfiguration {
            $c = [pscustomobject]@{ Settings = (Get-Content -LiteralPath (Join-Path $tool 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json); OfficeSources = $null }
            $c.Settings.windows.includeEnablementPackage = $false
            $c
        }
        (Get-StateOf (Get-TestState @($ekb)) 'w-ekb').Reason | Should -BeLike '*includeEnablementPackage*'
    }

    It 'signale les catégories absentes du dépôt et un fichier manquant sur le support' {
        $s = Get-TestState @(ConvertTo-TestItem 'w-lcu-KB9' 'windows-lcu' 'win11-x64' ($lcuFields + @{ resultingUbr = 9550 }) -Absent)
        @($s | Where-Object { -not $_.Id -and $_.State -eq 'MissingFromDepot' } | ForEach-Object { $_.Category }) | Should -Be @('dotnet', 'defender-platform', 'defender')
        (Get-StateOf $s 'w-lcu-KB9').State | Should -Be 'MissingFromDepot'
        (Get-StateOf $s 'w-lcu-KB9').Reason | Should -BeLike '*Fichier absent du support*'
    }

    It 'ignore les éléments d''une autre cible' {
        $s = Get-TestState @(ConvertTo-TestItem 'a-lcu' 'windows-lcu' 'win11-arm64' ($lcuFields + @{ resultingUbr = 9550 }))
        Get-StateOf $s 'a-lcu' | Should -BeNullOrEmpty
    }
}

Describe 'Get-OpUpdateState : .NET' {
    BeforeEach {
        Initialize-TestInfo
        Mock Get-MpComputerStatus { throw 'non simulé' }
        $script:netFile = [pscustomobject]@{ path = 'files/n/ndp.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.9347.1' } }
    }

    It 'à jour si le paquet est Installed en version égale ou supérieure, à installer sinon' -ForEach @(
        @{ PackageFullName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9347.1'; PackageState = 'Installed'; Expected = 'UpToDate' }
        @{ PackageFullName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9300.1'; PackageState = 'Installed'; Expected = 'Pending' }
        @{ PackageFullName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9347.1'; PackageState = 'Staged'; Expected = 'Pending' }
        @{ PackageFullName = 'Package_for_DotNetRollup~31bf3856ad364e35~amd64~~10.0.9400.1'; PackageState = 'Installed'; Expected = 'Pending' }
    ) {
        Mock Get-WindowsPackage { [pscustomobject]@{ PackageName = $PackageFullName; PackageState = $PackageState } }
        $s = Get-TestState @(ConvertTo-TestItem 'w-net' 'dotnet' 'win11-x64' @{ releaseDate = '2026-10-13' } @($netFile))
        (Get-StateOf $s 'w-net').State | Should -Be $Expected
    }

    It 'une cumulative par version de Windows 11 : seule celle de la build du PC est évaluée' {
        Mock Get-WindowsPackage { [pscustomobject]@{ PackageName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9363.1'; PackageState = 'Installed' } }
        $file25 = [pscustomobject]@{ path = 'files/a/ndp481-25.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.9363.1' } }
        $file26 = [pscustomobject]@{ path = 'files/b/ndp481-26.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.10008.1' } }
        $s = Get-TestState @(
            (ConvertTo-TestItem 'net-24-25' 'dotnet' 'win11-x64' @{ releaseDate = '2026-10-13'; baseBuilds = @(26100, 26200) } @($file25))
            (ConvertTo-TestItem 'net-26' 'dotnet' 'win11-x64' @{ releaseDate = '2026-10-13'; baseBuilds = @(26300) } @($file26)))
        (Get-StateOf $s 'net-24-25').State | Should -Be 'UpToDate'
        (Get-StateOf $s 'net-26').State | Should -Be 'NotApplicable'
        (Get-StateOf $s 'net-26').Reason | Should -BeLike '*26200 absente de baseBuilds*'
    }

    It 'aucune cumulative .NET pour la build du PC : absent du dépôt' {
        Mock Get-WindowsPackage { @() }
        $file26 = [pscustomobject]@{ path = 'files/b/ndp481-26.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.10008.1' } }
        $s = @(Get-TestState @(ConvertTo-TestItem 'net-26' 'dotnet' 'win11-x64' @{ baseBuilds = @(26300) } @($file26)))
        @($s | Where-Object { $_.Category -eq 'dotnet' -and $_.State -eq 'MissingFromDepot' }).Count | Should -Be 1
    }

    It 'liste DISM illisible : erreur' {
        Mock Get-WindowsPackage { throw 'élévation requise' }
        $s = Get-TestState @(ConvertTo-TestItem 'w-net' 'dotnet' 'win11-x64' @{} @($netFile))
        (Get-StateOf $s 'w-net').State | Should -Be 'Error'
        (Get-StateOf $s 'w-net').Reason | Should -BeLike '*élévation requise*'
    }

    It 'Windows 10 : fichier choisi selon la valeur Release, non applicable sans .NET 4.8' {
        Initialize-TestInfo -Target 'win10-x64' -Build 19045 -Ubr 7727
        $files = @(
            [pscustomobject]@{ path = 'files/a/ndp48.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup'; version = '10.0.9347.1' }; netRelease = [pscustomobject]@{ min = 528040; max = 533319 } }
            [pscustomobject]@{ path = 'files/b/ndp481.msu'; package = [pscustomobject]@{ name = 'Package_for_DotNetRollup_481'; version = '10.0.9347.1' }; netRelease = [pscustomobject]@{ min = 533320 } }
        )
        Mock Get-WindowsPackage { [pscustomobject]@{ PackageName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9347.1'; PackageState = 'Installed' } }
        Mock Get-ItemProperty -ParameterFilter { $Path -like '*NDP\v4\Full' } { [pscustomobject]@{ Release = 533325 } }
        (Get-StateOf (Get-TestState @(ConvertTo-TestItem 'w10-net' 'dotnet' 'win10-x64' @{} $files)) 'w10-net').State | Should -Be 'UpToDate'
        Mock Get-ItemProperty -ParameterFilter { $Path -like '*NDP\v4\Full' } { [pscustomobject]@{ Release = 528372 } }
        (Get-StateOf (Get-TestState @(ConvertTo-TestItem 'w10-net' 'dotnet' 'win10-x64' @{} $files)) 'w10-net').State | Should -Be 'Pending'
        Mock Get-ItemProperty -ParameterFilter { $Path -like '*NDP\v4\Full' } { [pscustomobject]@{ Release = 461814 } }
        $state = Get-StateOf (Get-TestState @(ConvertTo-TestItem 'w10-net' 'dotnet' 'win10-x64' @{} $files)) 'w10-net'
        $state.State | Should -Be 'NotApplicable'
        $state.Reason | Should -BeLike '*461814*'
    }
}

Describe 'Get-OpUpdateState : Defender' {
    BeforeEach {
        Initialize-TestInfo
        Mock Get-WindowsPackage { }
        $script:defender = @(
            ConvertTo-TestItem 'w-plat' 'defender-platform' 'win11-x64' @{ version = '4.18.26080.4' }
            ConvertTo-TestItem 'w-def' 'defender' 'win11-x64' @{ version = '1.459.600.0' }
        )
    }

    It 'compare plateforme et définitions aux versions du dépôt (mode <Mode>)' -ForEach @(@{ Mode = 'Normal' }, @{ Mode = 'Passive Mode' }) {
        Mock Get-MpComputerStatus { [pscustomobject]@{ AMRunningMode = $Mode; AMProductVersion = '4.18.26080.4'; AntivirusSignatureVersion = '1.459.553.0' } }
        $s = Get-TestState $defender
        (Get-StateOf $s 'w-plat').State | Should -Be 'UpToDate'
        (Get-StateOf $s 'w-def').State | Should -Be 'Pending'
    }

    It 'Defender désactivé ou muet : non applicable, jamais en erreur' {
        Mock Get-MpComputerStatus { [pscustomobject]@{ AMRunningMode = 'Not running'; AMProductVersion = '4.18.1.1'; AntivirusSignatureVersion = '1.1.1.1' } }
        @(Get-TestState $defender | Where-Object { $_.Id } | ForEach-Object { $_.State } | Sort-Object -Unique) | Should -Be @('NotApplicable')
        Mock Get-MpComputerStatus { throw 'service arrêté' }
        $s = Get-TestState $defender
        (Get-StateOf $s 'w-def').State | Should -Be 'NotApplicable'
        (Get-StateOf $s 'w-def').Reason | Should -BeLike '*service arrêté*'
    }
}

Describe 'Get-OpUpdateState : Office' {
    BeforeEach {
        Initialize-TestInfo
        Mock Get-WindowsPackage { }
        Mock Get-MpComputerStatus { throw 'non simulé' }
        $script:officeItem = ConvertTo-TestItem 'office-current-16.0.2.2' 'office-source' 'win11-x64' @{ channel = 'Current'; version = '16.0.2.2'; languages = @('fr-fr', 'en-us'); folder = 'office/current' }
        function Initialize-TestOffice([string[]]$Products = @('O365HomePremRetail'), [string]$Channel = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60', [string[]]$Languages = @('fr-fr'), [string]$Version = '16.0.2.2', [string]$Reported = '16.0.2.2', [string]$Platform = 'x64') {
            $script:info.Office = [pscustomobject]@{ Products = $Products; Languages = $Languages; ChannelId = $Channel; CdnChannelId = $Channel; UpdateChannelId = $Channel; ChannelMismatch = $false; Version = [version]$Version; VersionToReport = $Reported; Platform = $Platform }
        }
        function Get-OfficeState { @(Get-TestState @($officeItem) | Where-Object { $_.Category -eq 'office-source' })[0] }
    }

    It '<Case>' -ForEach @(
        @{ Case = 'à jour'; Arguments = @{}; State = 'UpToDate'; Reason = '*16.0.2.2*' }
        @{ Case = 'version plus ancienne : à installer'; Arguments = @{ Version = '16.0.1.1'; Reported = '16.0.1.1' }; State = 'Pending'; Reason = '*16.0.1.1 < 16.0.2.2*' }
        @{ Case = 'VersionToReport différent : à installer'; Arguments = @{ Reported = '16.0.3.3' }; State = 'Pending'; Reason = '*VersionToReport*' }
        @{ Case = 'Office 2019 : fin de support'; Arguments = @{ Products = @('ProPlus2019Retail') }; State = 'NotApplicable'; Reason = '*2016/2019*' }
        @{ Case = 'canal absent du dépôt'; Arguments = @{ Channel = '00000000-0000-0000-0000-000000000000' }; State = 'NotApplicable'; Reason = '*Canal absent*' }
        @{ Case = 'Office 32 bits'; Arguments = @{ Platform = 'x86' }; State = 'NotApplicable'; Reason = '*32 bits*' }
        @{ Case = 'langue absente de la source'; Arguments = @{ Languages = @('fr-fr', 'de-de') }; State = 'NotApplicable'; Reason = '*Langue absente*de-de*' }
    ) {
        Initialize-TestOffice @Arguments
        $s = Get-OfficeState
        $s.State | Should -Be $State
        $s.Reason | Should -BeLike $Reason
    }

    It 'aucun Office Click-to-Run : non applicable ; source attendue absente du manifeste : absente du dépôt' {
        (Get-OfficeState).Reason | Should -Be 'Aucun Office Click-to-Run.'
        Initialize-TestOffice -Channel '7983bac0-e531-40cf-be00-fd24fe66619c'
        (Get-OfficeState).State | Should -Be 'MissingFromDepot'
    }
}
