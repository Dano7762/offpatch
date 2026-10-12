# Relevé de l'état du PC (cahier des charges 8.2, 8.3, 9 ; R-04, R-08) sur registre et WMI simulés. Seul
# Get-OpPowerStatus lit le PC réel, en lecture seule.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }
    $esuIds = @((Get-OpConfiguration -Root $root).Settings.windows.esuActivationIds)

    function Initialize-TestIdentity([string]$Family, [int]$Build, [string]$Architecture) {
        $script:identity = [pscustomobject]@{ Family = $Family; CurrentBuild = $Build; Ubr = 7000; DisplayVersion = '22H2'; EditionId = 'Professional'; Caption = "Microsoft $Family Professionnel"; Architecture = $Architecture }
    }
}

Describe 'Get-OpSystemInfo' {
    BeforeEach {
        Initialize-TestIdentity 'Windows11' 26200 'x64'
        Mock Get-OpWindowsIdentity { $script:identity }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } { [pscustomobject]@{ Manufacturer = 'Fabricant '; Model = ' Modèle 1' } }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } { [pscustomobject]@{ SerialNumber = ' SN123 ' } }
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } { }
        Mock Get-OpOfficeInstallation { [pscustomobject]@{ Products = @('Home2024Retail') } }
        Mock Get-OpFreeSpace { [long]50GB }
        Mock Get-OpPowerStatus { [pscustomobject]@{ HasBattery = $true; OnBattery = $true; BatteryPercent = 80 } }
    }

    It 'relève Windows 11, le matériel, Office, l''espace et l''alimentation, sans requête ESU' {
        $i = Get-OpSystemInfo -Root $root
        $i.Target | Should -Be 'win11-x64'
        $i.CurrentBuild | Should -Be 26200
        $i.Manufacturer | Should -Be 'Fabricant'
        $i.Model | Should -Be 'Modèle 1'
        $i.SerialNumber | Should -Be 'SN123'
        $i.Esu | Should -BeNullOrEmpty
        $i.Office.Products | Should -Be @('Home2024Retail')
        $i.FreeSpaceBytes | Should -Be 50GB
        $i.Power.OnBattery | Should -BeTrue
        Should -Invoke Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } -Times 0 -Exactly
        Should -Invoke Get-OpFreeSpace -ParameterFilter { $Path -eq "$($env:SystemDrive)\" } -Times 1 -Exactly
    }

    It 'Windows 10 : ESU entreprise actif, avec l''année la plus haute sous licence' {
        Initialize-TestIdentity 'Windows10' 19045 'x64'
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
            [pscustomobject]@{ ID = $esuIds[0].ToUpperInvariant(); LicenseStatus = 1 }
            [pscustomobject]@{ ID = $esuIds[1]; LicenseStatus = 1 }
            [pscustomobject]@{ ID = $esuIds[2]; LicenseStatus = 5 }
        }
        $i = Get-OpSystemInfo -Root $root
        $i.Target | Should -Be 'win10-x64'
        $i.Esu.Status | Should -Be 'Active'
        $i.Esu.Year | Should -Be 2
        Should -Invoke Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' -and $Filter -eq (($esuIds | ForEach-Object { "ID='$_'" }) -join ' OR ') } -Times 1 -Exactly
    }

    It 'Windows 10 : ESU indétectable sans licence active, ou si la requête échoue' {
        Initialize-TestIdentity 'Windows10' 19045 'x64'
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } { [pscustomobject]@{ ID = $esuIds[0]; LicenseStatus = 0 } }
        $i = Get-OpSystemInfo -Root $root
        $i.Esu.Status | Should -Be 'Undetectable'
        $i.Esu.Detail | Should -BeNullOrEmpty
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } { throw 'service WMI arrêté' }
        $i = Get-OpSystemInfo -Root $root
        $i.Esu.Status | Should -Be 'Undetectable'
        $i.Esu.Detail | Should -BeLike '*service WMI arrêté*'
    }

    It 'une lecture secondaire en échec laisse sa valeur vide sans arrêter le relevé' {
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } { throw 'WMI' }
        Mock Get-OpPowerStatus { throw 'System.Windows.Forms absent' }
        Mock Get-OpOfficeInstallation { $null }
        $i = Get-OpSystemInfo -Root $root
        $i.Manufacturer | Should -BeNullOrEmpty
        $i.SerialNumber | Should -Be 'SN123'
        $i.Power | Should -BeNullOrEmpty
        $i.Office | Should -BeNullOrEmpty
    }

    It 'laisse Target vide si l''architecture est illisible' {
        Initialize-TestIdentity 'Windows11' 26200 $null
        (Get-OpSystemInfo -Root $root).Target | Should -BeNullOrEmpty
    }
}

Describe 'Get-OpOfficeInstallation' {
    BeforeEach {
        $script:c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun'
        Mock Get-ItemProperty -ParameterFilter { $Path -eq "$c2r\Configuration" } {
            [pscustomobject]@{
                ProductReleaseIds = 'O365HomePremRetail, VisioProRetail'
                Platform          = 'x64'
                InstallationPath  = 'C:\Program Files\Microsoft Office'
                CDNBaseUrl        = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
                UpdateChannel     = 'http://officecdn.microsoft.com/pr/7983BAC0-E531-40CF-BE00-FD24FE66619C'
                VersionToReport   = '16.0.2.2'
            }
        }
        function ConvertTo-TestKey([string]$Parent, [string]$Name) { [pscustomobject]@{ PSChildName = $Name; PSParentPath = "Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office\ClickToRun\ProductReleaseIDs\{guid}\$Parent" } }
        Mock Get-ChildItem -ParameterFilter { $Path -eq "$c2r\ProductReleaseIDs" } {
            ConvertTo-TestKey 'O365HomePremRetail.16' 'fr-fr'
            ConvertTo-TestKey 'O365HomePremRetail.16' 'x-none'
            ConvertTo-TestKey 'VisioProRetail.16' 'en-us'
            ConvertTo-TestKey 'VisioProRetail.16' 'fr-fr'
            ConvertTo-TestKey 'ProPlus2019Retail.16' 'de-de'
        }
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*\WINWORD.EXE' } { $false }
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*\EXCEL.EXE' } { $true }
        Mock Get-OpFileVersion { [version]'16.0.1.1' }
    }

    It 'renvoie $null sans Office Click-to-Run' {
        Mock Get-ItemProperty -ParameterFilter { $Path -eq "$c2r\Configuration" } { }
        Get-OpOfficeInstallation | Should -BeNullOrEmpty
    }

    It 'relève produits, langues des produits installés, canal et version de fichier' {
        $o = Get-OpOfficeInstallation
        $o.Products | Should -Be @('O365HomePremRetail', 'VisioProRetail')
        $o.Languages | Should -Be @('en-us', 'fr-fr')
        $o.ChannelId | Should -Be '7983bac0-e531-40cf-be00-fd24fe66619c'
        $o.CdnChannelId | Should -Be '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        $o.ChannelMismatch | Should -BeTrue
        $o.Version | Should -Be ([version]'16.0.1.1')
        $o.VersionFile | Should -Be 'EXCEL.EXE'
        $o.VersionToReport | Should -Be '16.0.2.2'
        Should -Invoke Get-OpFileVersion -ParameterFilter { $Path -eq 'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE' } -Times 1 -Exactly
    }

    It 'prend le canal de CDNBaseUrl sans UpdateChannel, et aucune version sans exécutable' {
        Mock Get-ItemProperty -ParameterFilter { $Path -eq "$c2r\Configuration" } {
            [pscustomobject]@{ ProductReleaseIds = 'Home2024Retail'; CDNBaseUrl = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'; InstallationPath = 'C:\Office' }
        }
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*\EXCEL.EXE' } { $false }
        $o = Get-OpOfficeInstallation
        $o.ChannelId | Should -Be '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        $o.ChannelMismatch | Should -BeFalse
        $o.Version | Should -BeNullOrEmpty
        $o.Languages | Should -BeNullOrEmpty
    }
}

Describe 'Get-OpPowerStatus' {
    It 'lit l''alimentation du PC sans erreur' {
        $p = Get-OpPowerStatus
        $p.PSObject.Properties.Name | Should -Be @('HasBattery', 'OnBattery', 'BatteryPercent')
        if (-not $p.HasBattery) { $p.OnBattery | Should -BeFalse }
    }
}
