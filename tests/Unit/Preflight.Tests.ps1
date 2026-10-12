# Contrôles préalables (cahier des charges 8.2) sur un relevé du PC simulé, et lectures du registre, de WMI et du
# réseau simulées. Rien n'est lu ni modifié sur le PC réel.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }
    $now = [datetime]'2026-10-20T12:00:00Z'

    # Relevé d'un PC dans le périmètre, que chaque test modifie.
    function Get-TestInfo {
        [pscustomobject]@{
            Caption = 'Microsoft Windows 11 Professionnel'; DisplayVersion = '25H2'; Family = 'Windows11'; CurrentBuild = 26200; Ubr = 9457
            Architecture = 'x64'; Target = 'win11-x64'; ProductType = 1; Is64BitOperatingSystem = $true; Is64BitProcess = $true
            Esu = $null; SystemDrive = 'C:'; FreeSpaceBytes = [long]100GB
            Power = [pscustomobject]@{ HasBattery = $true; OnBattery = $false; BatteryPercent = 90 }
        }
    }
    function Get-Check([object]$Info, [string]$Id) {
        @(Test-OpPreflight -Root $root -SystemInfo $Info -Now $now | Where-Object { $_.Id -eq $Id })[0]
    }
}

Describe 'Test-OpPreflight' {
    BeforeEach {
        Mock Test-OpElevated { $true }
        Mock Get-OpPendingReboot { @() }
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $true; Spp = $true; Storage = $true } }
        Mock Get-OpNetworkConnection { }
        Mock Read-OpManifest { [pscustomobject]@{ schemaVersion = 1; generatedAt = '2026-10-14T09:12:00Z'; items = @([pscustomobject]@{ id = 'x' }) } }
    }

    It 'PC dans le périmètre, hors ligne, dépôt récent : tous les contrôles sont Ok, dans l''ordre du tableau' {
        $checks = @(Test-OpPreflight -Root $root -SystemInfo (Get-TestInfo) -Now $now)
        @($checks | ForEach-Object { $_.Id }) | Should -Be @('Elevation', 'ProcessBitness', 'Target', 'PendingReboot', 'FreeSpace', 'Battery', 'DepotAge', 'RestorePoint', 'Network')
        @($checks | Where-Object { $_.Result -ne 'Ok' }) | Should -BeNullOrEmpty
        ($checks | Where-Object { $_.Id -eq 'DepotAge' }).Message | Should -BeLike '*il y a 6 jour*'
    }

    It 'bloque sans droits administrateur et sous PowerShell 32 bits' {
        Mock Test-OpElevated { $false }
        $info = Get-TestInfo
        $info.Is64BitProcess = $false
        (Get-Check $info 'Elevation').Result | Should -Be 'Blocking'
        (Get-Check $info 'ProcessBitness').Result | Should -Be 'Blocking'
    }

    It 'refuse un système hors périmètre : <Case>' -ForEach @(
        @{ Case = 'Windows Server'; Family = 'Windows11'; Build = 26100; Arch = 'x64'; Type = 3; Expected = '*Windows Server*' }
        @{ Case = 'x86'; Family = 'Windows10'; Build = 19045; Arch = 'x86'; Type = 1; Expected = '*architecture x86*' }
        @{ Case = 'Windows 10 21H2'; Family = 'Windows10'; Build = 19044; Arch = 'x64'; Type = 1; Expected = '*Windows 10 antérieur aux versions prises en charge (builds 19045)*' }
        @{ Case = 'Windows 10 ARM64'; Family = 'Windows10'; Build = 19045; Arch = 'arm64'; Type = 1; Expected = '*Windows 10 ARM64*' }
        @{ Case = 'Windows 11 23H2'; Family = 'Windows11'; Build = 22631; Arch = 'x64'; Type = 1; Expected = '*Windows 11 antérieur*(builds 26100, 26200, 26300)*' }
        @{ Case = 'Windows 11 26H1'; Family = 'Windows11'; Build = 28000; Arch = 'arm64'; Type = 1; Expected = '*version de Windows 11 non prise en charge*' }
    ) {
        $info = Get-TestInfo
        $info.Family = $Family; $info.CurrentBuild = $Build; $info.Architecture = $Arch; $info.ProductType = $Type
        $check = Get-Check $info 'Target'
        $check.Result | Should -Be 'Blocking'
        $check.Message | Should -BeLike $Expected
    }

    It 'accepte une nouvelle version de Windows 11 ajoutée à windows.supportedBuilds, sans changer le code' {
        $info = Get-TestInfo
        $info.CurrentBuild = 26400
        (Get-Check $info 'Target').Result | Should -Be 'Blocking'
        Mock Get-OpConfiguration {
            $c = [pscustomobject]@{ Settings = (Get-Content -LiteralPath (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json) }
            $c.Settings.windows.supportedBuilds.win11 = @(26100, 26200, 26300, 26400)
            $c
        }
        (Get-Check $info 'Target').Result | Should -Be 'Ok'
    }

    It 'avertit quand la cible du PC n''est pas dans settings.json' {
        $info = Get-TestInfo
        $info.Target = 'win11-arm64'; $info.Architecture = 'arm64'
        Mock Get-OpConfiguration {
            $c = [pscustomobject]@{ Settings = (Get-Content -LiteralPath (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json) }
            $c.Settings.targets = @('win11-x64')
            $c
        }
        $check = Get-Check $info 'Target'
        $check.Result | Should -Be 'Warning'
        $check.Message | Should -BeLike '*win11-arm64 absente*'
    }

    It 'Windows 10 : ESU actif Ok, sinon avertissement et étape Windows ignorée en mode auto' {
        $info = Get-TestInfo
        $info.Family = 'Windows10'; $info.CurrentBuild = 19045; $info.Target = 'win10-x64'
        $info.Esu = [pscustomobject]@{ Status = 'Active'; Year = 2; Detail = $null }
        (Get-Check $info 'Esu').Message | Should -BeLike '*année 2*'
        $info.Esu = [pscustomobject]@{ Status = 'Undetectable'; Year = $null; Detail = 'Licence ESU illisible : x' }
        $check = Get-Check $info 'Esu'
        $check.Result | Should -Be 'Warning'
        $check.Action | Should -Be 'SkipWindowsInAuto'
        $check.Message | Should -BeLike '*illisible : x*'
        @(Test-OpPreflight -Root $root -SystemInfo (Get-TestInfo) -Now $now | Where-Object { $_.Id -eq 'Esu' }) | Should -BeNullOrEmpty
    }

    It 'propose de redémarrer quand un redémarrage est en attente' {
        Mock Get-OpPendingReboot { @('CBS') }
        $check = Get-Check (Get-TestInfo) 'PendingReboot'
        $check.Result | Should -Be 'Warning'
        $check.Action | Should -Be 'ProposeReboot'
        $check.Message | Should -BeLike '*(CBS)*'
    }

    It 'bloque sous minFreeSpaceGB ou si l''espace est illisible' {
        $info = Get-TestInfo
        $info.FreeSpaceBytes = [long]16GB
        (Get-Check $info 'FreeSpace').Message | Should -BeLike '*16,0 Go libres, 17 Go*'
        (Get-Check $info 'FreeSpace').Result | Should -Be 'Blocking'
        $info.FreeSpaceBytes = $null
        (Get-Check $info 'FreeSpace').Result | Should -Be 'Blocking'
    }

    It 'avertit d''un portable sur batterie avant le mode auto' {
        $info = Get-TestInfo
        $info.Power.OnBattery = $true
        $check = Get-Check $info 'Battery'
        $check.Action | Should -Be 'ConfirmAutoMode'
        $check.Message | Should -BeLike '*(90 %)*'
    }

    It 'avertit d''un dépôt ancien ou vide' {
        Mock Read-OpManifest { [pscustomobject]@{ schemaVersion = 1; generatedAt = '2026-09-01T00:00:00Z'; items = @([pscustomobject]@{ id = 'x' }) } }
        (Get-Check (Get-TestInfo) 'DepotAge').Message | Should -BeLike '*il y a 49 jours*'
        Mock Read-OpManifest { [pscustomobject]@{ schemaVersion = 1; generatedAt = $null; items = @() } }
        (Get-Check (Get-TestInfo) 'DepotAge').Message | Should -BeLike '*Dépôt vide*'
        Mock Read-OpManifest { throw 'JSON invalide' }
        (Get-Check (Get-TestInfo) 'DepotAge').Message | Should -BeLike '*illisible*JSON invalide*'
    }

    It 'point de restauration : avertissement si la protection est inactive ou illisible, jamais bloquant' {
        Mock Get-OpSystemProtection { [pscustomobject]@{ Active = $false; Spp = $true; Storage = $false } }
        $check = Get-Check (Get-TestInfo) 'RestorePoint'
        $check.Result | Should -Be 'Warning'
        $check.Message | Should -BeLike '*SPP\Clients : True, clichés réservés : False*'
        Mock Get-OpSystemProtection { throw 'WMI' }
        (Get-Check (Get-TestInfo) 'RestorePoint').Result | Should -Be 'Warning'
    }

    It 'recommande le mode Avion quand le PC est connecté' {
        Mock Get-OpNetworkConnection { [pscustomobject]@{ Name = 'Réseau'; InterfaceAlias = 'Ethernet'; Connectivity = 'Internet' } }
        $check = Get-Check (Get-TestInfo) 'Network'
        $check.Result | Should -Be 'Warning'
        $check.Message | Should -BeLike '*Ethernet : Internet*mode Avion*'
    }
}

Describe 'Get-OpPendingReboot' {
    BeforeEach {
        Mock Test-Path { $false }
        Mock Get-ItemProperty { [pscustomobject]@{ PendingFileRenameOperations = @('', '') } }
    }

    It 'renvoie un tableau vide sans indicateur (valeur de renommage vide comprise)' {
        @(Get-OpPendingReboot) | Should -BeNullOrEmpty
    }

    It 'relève CBS, Windows Update et les renommages en attente' {
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*\Component Based Servicing\RebootPending' } { $true }
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*\WindowsUpdate\Auto Update\RebootRequired' } { $true }
        Mock Get-ItemProperty { [pscustomobject]@{ PendingFileRenameOperations = @('\??\C:\a.tmp', '') } }
        Get-OpPendingReboot | Should -Be @('CBS', 'WindowsUpdate', 'FileRename')
    }
}

Describe 'Get-OpSystemProtection' {
    BeforeEach {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' } { [pscustomobject]@{ DeviceID = '\\?\Volume{c}\' } }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } { [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = '\\?\Volume{c}\' } } }
        Mock Get-ItemProperty { [pscustomobject]@{ '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}' = @('\\?\Volume{c}\:(C%3A)') } }
    }

    It 'active seulement si SPP\Clients et Win32_ShadowStorage citent le volume système' {
        (Get-OpSystemProtection).Active | Should -BeTrue
    }

    It 'désaccord entre les deux indicateurs : inactive' {
        Mock Get-ItemProperty { [pscustomobject]@{ '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}' = @('\\?\Volume{d}\:(D%3A)') } }
        $p = Get-OpSystemProtection
        $p.Active | Should -BeFalse
        $p.Spp | Should -BeFalse
        $p.Storage | Should -BeTrue
    }
}

Describe 'Get-OpNetworkConnection' {
    It 'ne garde que les profils connectés, avec la meilleure connectivité' {
        Mock Get-NetConnectionProfile {
            [pscustomobject]@{ Name = 'A'; InterfaceAlias = 'Ethernet'; IPv4Connectivity = 'Internet'; IPv6Connectivity = 'NoTraffic' }
            [pscustomobject]@{ Name = 'B'; InterfaceAlias = 'Wi-Fi'; IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'LocalNetwork' }
            [pscustomobject]@{ Name = 'C'; InterfaceAlias = 'VPN'; IPv4Connectivity = 'Disconnected'; IPv6Connectivity = 'NoTraffic' }
        }
        $n = @(Get-OpNetworkConnection)
        @($n | ForEach-Object { "$($_.InterfaceAlias)=$($_.Connectivity)" }) | Should -Be @('Ethernet=Internet', 'Wi-Fi=LocalNetwork')
    }

    It 'mode Avion : aucun profil' {
        Mock Get-NetConnectionProfile { }
        @(Get-OpNetworkConnection) | Should -BeNullOrEmpty
    }
}
