# Exécuteur DISM (cahier des charges 8.4, R-14) : codes retour, nouvelle tentative sur 1618, jugement par la liste
# DISM et le journal de l'étape. dism.exe (Invoke-OpProcess), Get-WindowsPackage et Start-Sleep simulés : rien n'est
# installé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Invoke-OpProcess', 'Test-OpItemFileHash', 'Install-OpWindowsPackage') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }

    # Un dépôt simulé avec les fichiers de l'élément, rangés sous files/<sha256>/ comme le vrai.
    function Get-DismScene([string]$Category, [hashtable]$Fields = @{}, [string[]]$FileName = @('paquet.msu'), [object[]]$Package = @($null), [object[]]$NetRelease = @($null), [switch]$Corrupt) {
        $depot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $files = for ($i = 0; $i -lt $FileName.Count; $i++) {
            $tmp = Join-Path $depot "tmp$i"
            New-Item -ItemType Directory -Force -Path $depot | Out-Null
            Set-Content -Path $tmp -Value "paquet simulé $i" -Encoding UTF8
            $sha = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
            New-Item -ItemType Directory -Force -Path (Join-Path $depot "files\$sha") | Out-Null
            Move-Item -Path $tmp -Destination (Join-Path $depot "files\$sha\$($FileName[$i])")
            if ($Corrupt) { Add-Content -Path (Join-Path $depot "files\$sha\$($FileName[$i])") -Value 'altéré' }
            $entry = [ordered]@{ path = "files/$sha/$($FileName[$i])"; sha256 = $sha; size = 1 }
            if ($Package[$i]) { $entry.package = [pscustomobject]$Package[$i] }
            if ($NetRelease[$i]) { $entry.netRelease = [pscustomobject]$NetRelease[$i] }
            [pscustomobject]$entry
        }
        $item = [ordered]@{ id = "win11-x64-$Category-test"; category = $Category; files = @($files) }
        foreach ($k in $Fields.Keys) { $item[$k] = $Fields[$k] }
        [pscustomobject]@{ Depot = $depot; Logs = (Join-Path $depot 'session'); Item = [pscustomobject]$item }
    }

    # Codes successifs de dism.exe (le dernier se répète) ; le journal de l'étape reçoit $script:dismLog.
    function Use-DismRun([int[]]$Code, [string]$Log = 'Reboot required=yes') {
        $script:codes = $Code
        $script:call = 0
        $script:dismLog = $Log
        Mock Invoke-OpProcess {
            $logArg = @($ArgumentList | Where-Object { $_ -like '/LogPath:*' })[0]
            Set-Content -Path $logArg.Substring(9) -Value $script:dismLog -Encoding UTF8
            $c = $script:codes[[math]::Min($script:call, $script:codes.Count - 1)]
            $script:call++
            [pscustomobject]@{ ExitCode = $c; TimedOut = $false; StdOut = "HOTPATCHUTIL GetSystemReadyForHotPatchStatus`r`nThe operation completed successfully."; StdErr = ''; Seconds = 1 }
        }
    }
    function Use-PackageList([object[]]$Package) {
        $script:packages = @($Package | ForEach-Object { [pscustomobject]$_ })
        Mock Get-WindowsPackage { $script:packages }
    }
}

Describe 'Install-OpWindowsPackage' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-OpLog {}
    }

    Context 'cumulatives et checkpoint' {
        It 'lance dism.exe par son chemin complet et réussit sur 3010 avec la cumulative en attente' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun 3010
            Use-PackageList @(@{ PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.9550.1.10'; PackageState = 'InstallPending' })
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'UpToDate'
            $r.RebootRequired | Should -BeTrue
            $r.Package | Should -Match '26100\.9550'
            Test-Path $r.LogPath | Should -BeTrue
            $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
            Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $dism -and $NoTimeout -and ($ArgumentList[0..2] -join ' ') -eq '/English /Online /Add-Package' -and $ArgumentList -contains '/NoRestart' -and $ArgumentList[3] -like '/PackagePath:*paquet.msu'
            }
            Should -Invoke Write-OpLog -ParameterFilter { $Message -match 'completed successfully' -and $Message -notmatch 'HOTPATCHUTIL' }
        }

        It 'réussit une checkpoint par la version de Package_for_RollupFix' {
            $s = Get-DismScene 'windows-checkpoint' @{ resultingUbr = 1742 }
            Use-DismRun 0 'Reboot required=no'
            Use-PackageList @(@{ PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.1742.1.10'; PackageState = 'Installed' })
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'UpToDate'
            $r.RebootRequired | Should -BeFalse
        }

        It 'ne se satisfait pas d''une cumulative plus ancienne déjà installée' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun 0 'Reboot required=no'
            Use-PackageList @(@{ PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.9457.1.10'; PackageState = 'Installed' })
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match 'sans installer le paquet'
        }

        It 'passe en NotApplicable avec avertissement quand le journal contient CBS HRESULT=0x800f081e' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun 0 'Error in operation: the package is not applicable. (CBS HRESULT=0x800f081e)'
            Use-PackageList @()
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'NotApplicable'
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -match 'jugé applicable par le planificateur' }
        }
    }

    Context 'codes retour' {
        It 'est en erreur avec le code <Code> sans consulter la liste DISM' -TestCases @(
            @{ Code = 3; Hex = '0x00000003' }
            @{ Code = -905928695; Hex = '0xCA00A009' }
            @{ Code = -2146498529; Hex = '0x800F081F' }
        ) {
            param($Code, $Hex)
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun $Code
            Use-PackageList @()
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match ([regex]::Escape($Hex))
            Should -Invoke Get-WindowsPackage -Times 0 -Exactly
        }

        It 'retente une seule fois après 5 minutes sur <Code> (autre installation en cours)' -TestCases @(
            @{ Code = 1618 }
            @{ Code = -2147023278 }
        ) {
            param($Code)
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun @($Code, 3010)
            Use-PackageList @(@{ PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.9550.1.10'; PackageState = 'InstallPending' })
            (Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs).State | Should -Be 'UpToDate'
            Should -Invoke Invoke-OpProcess -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 300 }
        }

        It 'est en erreur si la seconde tentative renvoie encore 1618' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun 1618
            Use-PackageList @()
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'Error'
            $r.ExitCode | Should -Be 1618
            Should -Invoke Invoke-OpProcess -Times 2 -Exactly
        }
    }

    Context 'enablement package, .NET, SSU' {
        It 'reconnaît l''enablement package par son KB' {
            $s = Get-DismScene 'windows-ekb' @{ kb = 'KB0000009' }
            Use-DismRun 3010
            Use-PackageList @(@{ PackageName = 'Package_for_KB0000009~31bf3856ad364e35~amd64~~26100.1.1.1'; PackageState = 'InstallPending' })
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'UpToDate'
            $r.RebootRequired | Should -BeTrue
        }

        It 'choisit le fichier .NET d''après Release et vérifie le paquet par nom et version' {
            $s = Get-DismScene 'dotnet' -FileName 'ndp48.msu', 'ndp481.msu' `
                -Package @{ name = 'Package_for_DotNetRollup'; version = '10.0.9310.1' }, @{ name = 'Package_for_DotNetRollup_481'; version = '10.0.9310.1' } `
                -NetRelease @{ min = 528040; max = 533319 }, @{ min = 533320 }
            Mock Get-ItemProperty { [pscustomobject]@{ Release = 533325 } } -ParameterFilter { $Name -eq 'Release' }
            Use-DismRun 0 'Reboot required=no'
            Use-PackageList @(
                @{ PackageName = 'Package_for_DotNetRollup~31bf3856ad364e35~amd64~~10.0.9310.1'; PackageState = 'Installed' }
                @{ PackageName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9310.1'; PackageState = 'Installed' })
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'UpToDate'
            $r.Package | Should -Match '^Package_for_DotNetRollup_481~'
            Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { $ArgumentList[3] -like '*ndp481.msu' }
        }

        It 'juge la SSU sur le seul journal : <Cas>' -TestCases @(
            @{ Cas = 'installée'; Log = 'Reboot required=no'; State = 'UpToDate' }
            @{ Cas = 'non applicable'; Log = 'CBS HRESULT=0x800f081e'; State = 'NotApplicable' }
        ) {
            param($Cas, $Log, $State)
            $s = Get-DismScene 'windows-ssu'
            Use-DismRun 0 $Log
            Use-PackageList @()
            (Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs).State | Should -Be $State -Because $Cas
            Should -Invoke Get-WindowsPackage -Times 0 -Exactly
        }
    }

    Context 'garde-fous' {
        It 'ne lance pas DISM si le fichier ne correspond plus au manifeste' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 } -Corrupt
            Use-DismRun 0
            $r = Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match 'SHA-256'
            Should -Invoke Invoke-OpProcess -Times 0 -Exactly
        }

        It 'respecte -WhatIf' {
            $s = Get-DismScene 'windows-lcu' @{ resultingUbr = 9550 }
            Use-DismRun 0
            Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-OpProcess -Times 0 -Exactly
        }

        It 'refuse une catégorie Defender ou Office' {
            $s = Get-DismScene 'defender'
            { Install-OpWindowsPackage -Item $s.Item -Depot $s.Depot -LogDirectory $s.Logs } | Should -Throw '*non prise en charge*'
        }
    }
}
