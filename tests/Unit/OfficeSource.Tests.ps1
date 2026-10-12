# Téléchargement des sources Office par setup.exe /download (cahier des charges 7.1, R-07) : version lue dans
# v64.cab (fabriqué avec makecab), appel de l'ODT en mode download, branchement dans Invoke-OpDepotUpdate et
# Format-OpDepotPlan. Aucun accès réseau, setup.exe n'est jamais lancé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }

    # Source Office simulée : un dossier par version dans Office\Data et, si $Index est donné, un v64.cab dont
    # v64.hash porte cette version en deuxième ligne. Le cabinet contient deux fichiers, comme le vrai (avec un
    # seul fichier, expand.exe ignorerait -F).
    function Initialize-TestSource([string]$Name, [string[]]$Versions, [string]$Index) {
        $data = Join-Path $TestDrive "$Name\Office\Data"
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        foreach ($v in $Versions) { New-Item -ItemType Directory -Force -Path (Join-Path $data $v) | Out-Null }
        if ($Index) {
            $cabSource = Join-Path $TestDrive "$Name-cab"
            New-Item -ItemType Directory -Force -Path $cabSource | Out-Null
            [IO.File]::WriteAllText((Join-Path $cabSource 'v64.hash'), "0123456789ABCDEF`r`n$Index`r`n")
            [IO.File]::WriteAllText((Join-Path $cabSource 'VersionDescriptor.xml'), "<Version><Available Build=`"$Index`" /></Version>")
            $ddf = Join-Path $cabSource 'v64.ddf'
            [IO.File]::WriteAllLines($ddf, @('.OPTION EXPLICIT', '.Set CabinetNameTemplate=v64.cab', ".Set DiskDirectoryTemplate=$data",
                    '.Set Cabinet=on', '.Set Compress=on', '.Set InfFileName=NUL', '.Set RptFileName=NUL',
                    "`"$(Join-Path $cabSource 'v64.hash')`"", "`"$(Join-Path $cabSource 'VersionDescriptor.xml')`""))
            & (Join-Path $env:SystemRoot 'System32\makecab.exe') /F $ddf | Out-Null
        }
        Join-Path $TestDrive $Name
    }
    function Initialize-TestTool([string]$Name) {
        $tool = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path (Join-Path $tool 'tools\odt') | Out-Null
        Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
        Set-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Value 'simulé' -Encoding ASCII
        $tool
    }
    function Get-TestSourceRequest([string]$Tool) {
        [pscustomobject]@{ Id = 'current'; Channel = 'Current'; Languages = @('fr-fr', 'en-us'); SourcePath = (Join-Path $Tool 'depot\office\current'); Xml = '<Configuration />' }
    }
}

Describe 'Get-OpOfficeSourceVersion' {
    It 'renvoie $null pour une source vide ou absente' {
        Get-OpOfficeSourceVersion -Path (Join-Path $TestDrive 'absente') -WorkFolder (Join-Path $TestDrive 'w0') | Should -BeNullOrEmpty
        Get-OpOfficeSourceVersion -Path (Initialize-TestSource 'vide' @()) -WorkFolder (Join-Path $TestDrive 'w0') | Should -BeNullOrEmpty
    }

    It 'lit la version désignée par v64.cab, pas la plus élevée, et supprime le dossier de travail' {
        $src = Initialize-TestSource 's1' @('16.0.17932.20976', '16.0.17932.21000') '16.0.17932.20976'
        $work = Join-Path $TestDrive 'w1'
        $r = Get-OpOfficeSourceVersion -Path $src -WorkFolder $work
        $r.Version | Should -Be ([version]'16.0.17932.20976')
        $r.FromIndex | Should -BeTrue
        $r.Versions | Should -Be @([version]'16.0.17932.20976', [version]'16.0.17932.21000')
        Test-Path $work | Should -BeFalse
    }

    It 'sans v64.cab, retient la version la plus élevée (comparée comme version) et le signale' {
        $src = Initialize-TestSource 's2' @('16.0.9999.1', '16.0.17932.20976')
        $r = Get-OpOfficeSourceVersion -Path $src -WorkFolder (Join-Path $TestDrive 'w2')
        $r.Version | Should -Be ([version]'16.0.17932.20976')
        $r.FromIndex | Should -BeFalse
    }

    It 'refuse un index qui désigne une version absente ou illisible' {
        $src = Initialize-TestSource 's3' @('16.0.17932.20976') '16.0.17932.21000'
        { Get-OpOfficeSourceVersion -Path $src -WorkFolder (Join-Path $TestDrive 'w3') } | Should -Throw '*incohérent*16.0.17932.21000*'
        $src = Initialize-TestSource 's4' @('16.0.17932.20976') 'pas-une-version'
        { Get-OpOfficeSourceVersion -Path $src -WorkFolder (Join-Path $TestDrive 'w4') } | Should -Throw '*non reconnu*'
    }
}

Describe 'Save-OpOfficeSource' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Invoke-OpOfficeSetup { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; OdtLogs = @() } }
    }

    It 'lance setup.exe /download avec le XML de la source et relève une nouvelle version' {
        $tool = Initialize-TestTool 'o1'
        $request = Get-TestSourceRequest $tool
        $script:calls = 0
        Mock Get-OpOfficeSourceVersion { $script:calls++; if ($script:calls -gt 1) { [pscustomobject]@{ Version = [version]'16.0.20430.20140'; FromIndex = $true } } }
        Mock Invoke-OpOfficeSetup {
            $script:xml = [IO.File]::ReadAllText($ConfigPath)
            [pscustomobject]@{ ExitCode = 0; TimedOut = $false; OdtLogs = @() }
        }
        $r = Save-OpOfficeSource -Source $request -SetupPath (Join-Path $tool 'tools\odt\setup.exe') -Root $tool -Confirm:$false
        $r.Version | Should -Be ([version]'16.0.20430.20140')
        $r.PreviousVersion | Should -BeNullOrEmpty
        $r.Updated | Should -BeTrue
        $r.Languages | Should -Be @('fr-fr', 'en-us')
        $script:xml | Should -Be '<Configuration />'
        Test-Path $request.SourcePath | Should -BeTrue
        Should -Invoke Invoke-OpOfficeSetup -Times 1 -Exactly -ParameterFilter {
            $Mode -eq 'download' -and $ConfigPath -eq (Join-Path $tool 'depot\.tmp\office-current.xml') -and $SetupPath -like '*\tools\odt\setup.exe' -and $TimeoutMinutes -eq 240
        }
    }

    It 'déclare la source à jour quand la version ne change pas' {
        $tool = Initialize-TestTool 'o2'
        Mock Get-OpOfficeSourceVersion { [pscustomobject]@{ Version = [version]'16.0.20430.20140'; FromIndex = $true } }
        $r = Save-OpOfficeSource -Source (Get-TestSourceRequest $tool) -SetupPath (Join-Path $tool 'tools\odt\setup.exe') -Root $tool -Confirm:$false
        $r.Updated | Should -BeFalse
        $r.PreviousVersion | Should -Be ([version]'16.0.20430.20140')
    }

    It 'lève une erreur sur <Case>' -ForEach @(
        @{ Case = 'un code retour non nul'; Run = @{ ExitCode = 17002; TimedOut = $false }; Version = $true; Expected = '*code 17002*' }
        @{ Case = 'un délai dépassé'; Run = @{ ExitCode = -1; TimedOut = $true }; Version = $true; Expected = '*délai de 240 min*' }
        @{ Case = 'une source sans version'; Run = @{ ExitCode = 0; TimedOut = $false }; Version = $false; Expected = '*aucune version*' }
    ) {
        $tool = Initialize-TestTool "o3-$($Run.ExitCode)-$Version"
        Mock Invoke-OpOfficeSetup { [pscustomobject]$Run }
        if ($Version) { Mock Get-OpOfficeSourceVersion { [pscustomobject]@{ Version = [version]'16.0.1.1'; FromIndex = $true } } }
        else { Mock Get-OpOfficeSourceVersion {} }
        { Save-OpOfficeSource -Source (Get-TestSourceRequest $tool) -SetupPath (Join-Path $tool 'tools\odt\setup.exe') -Root $tool -Confirm:$false } | Should -Throw $Expected
    }

    It 'refuse sans setup.exe et ne fait rien avec -WhatIf' {
        $tool = Initialize-TestTool 'o4'
        Mock Get-OpOfficeSourceVersion {}
        { Save-OpOfficeSource -Source (Get-TestSourceRequest $tool) -SetupPath (Join-Path $tool 'absent\setup.exe') -Root $tool -Confirm:$false } | Should -Throw '*setup.exe absent*'
        Save-OpOfficeSource -Source (Get-TestSourceRequest $tool) -SetupPath (Join-Path $tool 'tools\odt\setup.exe') -Root $tool -WhatIf
        Should -Invoke Invoke-OpOfficeSetup -Times 0 -Exactly
        Test-Path (Join-Path $tool 'depot\office\current') | Should -BeFalse
    }
}

Describe 'Invoke-OpDepotUpdate et Format-OpDepotPlan : sources Office' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Get-OpDepotPlan {}
        Mock Get-OpFreeSpace { [long]100MB }
        Mock Invoke-OpDepotPurge { [pscustomobject]@{ RemovedItems = @(); FreedBytes = [long]0; Orphans = @() } }
        Mock Get-OpOdtPlan { [pscustomobject]@{ UpToDate = $true; Version = [version]'16.0.20326.20112'; InstalledVersion = [version]'16.0.20326.20112'; SetupPath = (Join-Path $Root 'tools\odt\setup.exe'); Error = $null } }
    }

    It 'télécharge chaque source configurée, compte un échec sans arrêter les autres et affiche le résultat' {
        $tool = Initialize-TestTool 'u1'
        Mock Save-OpOfficeSource {
            if ($Source.Id -eq 'perpetualvl2021') { throw 'setup.exe /download a renvoyé le code 17002' }
            [pscustomobject]@{ Id = $Source.Id; Channel = $Source.Channel; Version = [version]'16.0.20430.20140'; Updated = ($Source.Id -eq 'current') }
        }
        $r = Invoke-OpDepotUpdate -Root $tool -Confirm:$false
        Should -Invoke Save-OpOfficeSource -Times 3 -Exactly
        $r.ErrorCount | Should -Be 1
        @($r.Office).Count | Should -Be 3
        $text = (Format-OpDepotPlan -Result $r) -join "`n"
        $text | Should -Match 'Source Office current \[nouvelle version\] : 16\.0\.20430\.20140 \(Current\)'
        $text | Should -Match 'Source Office perpetualvl2024 \[à jour\]'
        $text | Should -Match 'Source Office perpetualvl2021 \[ÉCHEC\] : .*17002'
    }

    It 'ne lance aucun /download avec -ListOnly ni sans source Office' {
        $tool = Initialize-TestTool 'u2'
        Mock Save-OpOfficeSource {}
        $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'Sources Office : téléchargées par setup\.exe /download'
        Mock Get-OpOdtPlan {}
        $r = Invoke-OpDepotUpdate -Root $tool -Confirm:$false
        @($r.Office).Count | Should -Be 0
        Should -Invoke Save-OpOfficeSource -Times 0 -Exactly
    }
}
