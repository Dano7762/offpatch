# Récupération et mise à jour de l'ODT dans tools\odt (cahier des charges 7.1, R-07) : lien lu sur la page réelle du
# Centre de téléchargement (fixture), comparaison avec le setup.exe présent, téléchargement, vérification,
# extraction et remplacement, branchement dans Invoke-OpDepotUpdate et Format-OpDepotPlan. Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }
    $script:page = [System.IO.File]::ReadAllText((Join-Path $root 'tests\Fixtures\catalog\odt-download-page.html'))
    $script:configuration = [pscustomobject]@{
        Settings = Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    function Initialize-TestTool([string]$Name, [string]$Setup) {
        $tool = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path $tool | Out-Null
        Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
        if ($Setup) {
            New-Item -ItemType Directory -Force -Path (Join-Path $tool 'tools\odt') | Out-Null
            Set-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Value $Setup -Encoding ASCII
        }
        $tool
    }
    function Get-OdtPlan([string]$Tool, [hashtable]$Extra = @{}) {
        $plan = [pscustomobject]@{
            FileName = 'officedeploymenttool_20326-20112.exe'; Url = 'https://h/officedeploymenttool_20326-20112.exe'; Version = [version]'16.0.20326.20112'
            InstalledVersion = $null; SetupPath = (Join-Path $Tool 'tools\odt\setup.exe'); UpToDate = $false; SizeBytes = [long]3522096; Hosts = @('h'); Error = $null
        }
        foreach ($k in $Extra.Keys) { $plan.$k = $Extra[$k] }
        $plan
    }
}

Describe 'Get-OpOdtPlan' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Invoke-OpWebRequest { $script:page }
        Mock Resolve-OpDownloadUrl { [pscustomobject]@{ Url = $Url; Hosts = @(([uri]$Url).Host); SizeBytes = [long]3522096 } }
    }

    It 'lit la version et le lien sur la page réelle, sans ODT présent' {
        $tool = Initialize-TestTool 'p1'
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root $tool
        $p.Error | Should -BeNullOrEmpty
        $p.FileName | Should -Be 'officedeploymenttool_20326-20112.exe'
        $p.Version | Should -Be ([version]'16.0.20326.20112')
        $p.Url | Should -Match '^https://download\.microsoft\.com/download/[^/]+/officedeploymenttool_20326-20112\.exe$'
        $p.InstalledVersion | Should -BeNullOrEmpty
        $p.UpToDate | Should -BeFalse
        $p.SizeBytes | Should -Be 3522096
        $p.Hosts | Should -Be @('download.microsoft.com')
        $p.SetupPath | Should -Be (Join-Path $tool 'tools\odt\setup.exe')
    }

    It 'déclare l''ODT à jour sans résoudre le lien quand setup.exe a la même version ou plus' {
        $tool = Initialize-TestTool 'p2' 'ancien'
        Mock Get-OpFileVersion { [version]'16.0.20326.20112' }
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root $tool
        $p.UpToDate | Should -BeTrue
        $p.InstalledVersion | Should -Be ([version]'16.0.20326.20112')
        Should -Invoke Resolve-OpDownloadUrl -Times 0 -Exactly
    }

    It 'demande la nouvelle version quand setup.exe est plus ancien' {
        $tool = Initialize-TestTool 'p3' 'ancien'
        Mock Get-OpFileVersion { [version]'16.0.19029.20136' }
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root $tool
        $p.UpToDate | Should -BeFalse
        $p.InstalledVersion | Should -Be ([version]'16.0.19029.20136')
        Should -Invoke Resolve-OpDownloadUrl -Times 1 -Exactly
    }

    It 'retient la version la plus élevée quand la page cite plusieurs liens' {
        Mock Invoke-OpWebRequest { '<a href="https://h/x/officedeploymenttool_9999-1.exe"></a><a href="https://h/y/officedeploymenttool_20326-20112.exe"></a>' }
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root (Initialize-TestTool 'p4')
        $p.FileName | Should -Be 'officedeploymenttool_20326-20112.exe'
    }

    It 'porte une erreur, sans exception, quand <Cas>' -ForEach @(
        @{ Name = 'p5a'; Cas = 'la page ne contient pas de lien'; Page = '<html>autre page</html>'; Pattern = '*introuvable*structure de la page inconnue*' }
        @{ Name = 'p5b'; Cas = 'la page est injoignable'; Page = $null; Pattern = '*Page de l''ODT illisible*HTTP 503*' }
    ) {
        if ($null -eq $Page) { Mock Invoke-OpWebRequest { throw 'HTTP 503' } } else { Mock Invoke-OpWebRequest { $Page } }
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root (Initialize-TestTool $Name)
        $p.Error | Should -BeLike $Pattern
        $p.UpToDate | Should -BeFalse
    }

    It 'refuse une page dont l''hôte est absent de allowedDomains, sans la demander' {
        $c = [pscustomobject]@{ Settings = $script:configuration.Settings | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
        $c.Settings.downloadPages.officeDeploymentToolPage = 'https://exemple.invalid/odt'
        $p = Get-OpOdtPlan -Configuration $c -Root (Initialize-TestTool 'p6')
        $p.Error | Should -BeLike '*exemple.invalid absent de allowedDomains*'
        Should -Invoke Invoke-OpWebRequest -Times 0 -Exactly
    }

    It 'porte l''erreur de résolution du lien (hôte refusé)' {
        Mock Resolve-OpDownloadUrl { throw 'Hôte non autorisé : autre.example' }
        $p = Get-OpOdtPlan -Configuration $script:configuration -Root (Initialize-TestTool 'p7')
        $p.Error | Should -Be 'Hôte non autorisé : autre.example'
    }
}

Describe 'Save-OpOdt' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Save-OpDownload {
            New-Item -ItemType Directory -Force -Path (Split-Path -Path $Destination -Parent) | Out-Null
            Set-Content -Path $Destination -Value 'odt' -Encoding ASCII
            [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $false; SizeBytes = [long]3 }
        }
        Mock Confirm-OpDownloadIntegrity { [pscustomobject]@{ Path = $Path; Sha256 = 'x'; Sha1 = 'y' } }
        Mock Invoke-OpProcess {
            $folder = $ArgumentList[1] -replace '^/extract:', ''
            New-Item -ItemType Directory -Force -Path $folder | Out-Null
            Set-Content -Path (Join-Path $folder 'setup.exe') -Value 'nouveau' -Encoding ASCII
            Set-Content -Path (Join-Path $folder 'configuration-Office365-x64.xml') -Value '<Configuration />' -Encoding ASCII
            [pscustomobject]@{ ExitCode = 0; TimedOut = $false }
        }
        Mock Get-OpFileVersion { [version]'16.0.20326.20112' }
        Mock Test-OpElevated { $true }
    }

    It 'refuse avant tout téléchargement sans droits d''administrateur (extracteur requireAdministrator)' {
        $tool = Initialize-TestTool 's0' 'ancien'
        Mock Test-OpElevated { $false }
        { Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false } | Should -Throw '*droits d''administrateur*Lancer-OffPatch.cmd*'
        Should -Invoke Save-OpDownload -Times 0 -Exactly
    }

    It 'télécharge, vérifie, extrait et remplace setup.exe, puis supprime le dossier de travail' {
        $tool = Initialize-TestTool 's1' 'ancien'
        $r = Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false
        $r.Version | Should -Be ([version]'16.0.20326.20112')
        (Get-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Raw).Trim() | Should -Be 'nouveau'
        @(Get-ChildItem -Path (Join-Path $tool 'tools\odt') -Name) | Should -Be @('setup.exe')
        Test-Path (Join-Path $tool 'depot\.tmp\odt') | Should -BeFalse
        Should -Invoke Save-OpDownload -Times 1 -Exactly -ParameterFilter { $ExpectedSize -eq 3522096 -and $Destination -like '*\depot\.tmp\odt\officedeploymenttool_20326-20112.exe' }
        Should -Invoke Confirm-OpDownloadIntegrity -Times 1 -Exactly -ParameterFilter { $Path -like '*officedeploymenttool_20326-20112.exe' }
        Should -Invoke Confirm-OpDownloadIntegrity -Times 1 -Exactly -ParameterFilter { $Path -like '*\extract\setup.exe' }
        Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/quiet' -and $ArgumentList[1] -like '/extract:*\depot\.tmp\odt\extract' }
    }

    It 'crée tools\odt quand l''ODT est absent' {
        $tool = Initialize-TestTool 's2'
        Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false | Out-Null
        Test-Path (Join-Path $tool 'tools\odt\setup.exe') | Should -BeTrue
    }

    It 'garde l''ancien setup.exe et le fichier téléchargé quand <Cas>' -ForEach @(
        @{ Name = 's3a'; Cas = 'l''extraction échoue'; Run = @{ ExitCode = 5; TimedOut = $false }; Pattern = '*code retour 5*' }
        @{ Name = 's3b'; Cas = 'l''extraction dépasse le délai'; Run = @{ ExitCode = $null; TimedOut = $true }; Pattern = '*délai*dépassé*' }
    ) {
        $tool = Initialize-TestTool $Name 'ancien'
        Mock Invoke-OpProcess { [pscustomobject]$Run }
        { Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false } | Should -Throw $Pattern
        (Get-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Raw).Trim() | Should -Be 'ancien'
        Test-Path (Join-Path $tool 'depot\.tmp\odt\officedeploymenttool_20326-20112.exe') | Should -BeTrue
    }

    It 'refuse une extraction sans setup.exe' {
        $tool = Initialize-TestTool 's4' 'ancien'
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = 0; TimedOut = $false } }
        { Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false } | Should -Throw '*setup.exe absent*'
    }

    It 'refuse un setup.exe extrait dont la signature est rejetée' {
        $tool = Initialize-TestTool 's5' 'ancien'
        Mock Confirm-OpDownloadIntegrity -ParameterFilter { $Path -like '*\extract\setup.exe' } { throw 'Signature refusée' }
        { Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false } | Should -Throw 'Signature refusée'
        (Get-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Raw).Trim() | Should -Be 'ancien'
    }

    It 'signale sans refuser une version de setup.exe différente de celle du nom du fichier' {
        $tool = Initialize-TestTool 's6'
        Mock Get-OpFileVersion { [version]'16.0.20326.20114' }
        $r = Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -Confirm:$false
        $r.Version | Should -Be ([version]'16.0.20326.20114')
        Should -Invoke Write-OpLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*16.0.20326.20114*16.0.20326.20112 annoncée*' }
    }

    It 'ne fait rien quand l''ODT est à jour, lève l''erreur d''un plan refusé' {
        $tool = Initialize-TestTool 's7' 'ancien'
        $r = Save-OpOdt -Plan (Get-OdtPlan $tool @{ UpToDate = $true; InstalledVersion = [version]'16.0.20326.20112' }) -Configuration $script:configuration -Root $tool -Confirm:$false
        $r.Version | Should -Be ([version]'16.0.20326.20112')
        { Save-OpOdt -Plan (Get-OdtPlan $tool @{ Error = 'Hôte refusé' }) -Configuration $script:configuration -Root $tool -Confirm:$false } | Should -Throw '*Hôte refusé*'
        Should -Invoke Save-OpDownload -Times 0 -Exactly
    }

    It 'respecte -WhatIf' {
        $tool = Initialize-TestTool 's8' 'ancien'
        Save-OpOdt -Plan (Get-OdtPlan $tool) -Configuration $script:configuration -Root $tool -WhatIf
        Should -Invoke Save-OpDownload -Times 0 -Exactly
        Should -Invoke Invoke-OpProcess -Times 0 -Exactly
        (Get-Content -Path (Join-Path $tool 'tools\odt\setup.exe') -Raw).Trim() | Should -Be 'ancien'
    }
}

Describe 'Invoke-OpDepotUpdate et Format-OpDepotPlan : ODT' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Get-OpDepotPlan {}
        Mock Get-OpFreeSpace { [long]100MB }
        Mock Invoke-OpDepotPurge { [pscustomobject]@{ RemovedItems = @(); FreedBytes = [long]0; Orphans = @() } }
        Mock Save-OpOdt { [pscustomobject]@{ Version = $Plan.Version; Path = $Plan.SetupPath } }
        Mock Save-OpOfficeSource { [pscustomobject]@{ Id = $Source.Id; Channel = $Source.Channel; Version = [version]'16.0.1.1'; Updated = $false } } # OfficeSource.Tests.ps1
        Mock ConvertTo-OpOfficeManifestItem { [pscustomobject]@{ id = "office-$($Result.Id)-$($Result.Version)"; category = 'office-source'; folder = $Folder; files = @() } }
        Mock Save-OpManifest {}
    }

    It '-ListOnly compte l''ODT à télécharger et l''affiche, sans le télécharger' {
        $tool = Initialize-TestTool 'u1'
        Mock Get-OpOdtPlan { Get-OdtPlan $Root }
        $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
        $r.DownloadCount | Should -Be 1
        $r.DownloadBytes | Should -Be 3522096
        $r.ErrorCount | Should -Be 0
        Should -Invoke Save-OpOdt -Times 0 -Exactly
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'ODT \[à télécharger\] : version 16\.0\.20326\.20112, officedeploymenttool_20326-20112\.exe, 3,4 Mo'
    }

    It 'met à jour l''ODT pendant le téléchargement et l''affiche' {
        $tool = Initialize-TestTool 'u2'
        Mock Get-OpOdtPlan { Get-OdtPlan $Root }
        $r = Invoke-OpDepotUpdate -Root $tool -Confirm:$false
        $r.OdtUpdated | Should -BeTrue
        $r.ErrorCount | Should -Be 0
        Should -Invoke Save-OpOdt -Times 1 -Exactly
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'ODT \[mis à jour\] : version 16\.0\.20326\.20112'
    }

    It 'compte l''échec de la mise à jour de l''ODT sans arrêter la mise à jour du dépôt' {
        $tool = Initialize-TestTool 'u3'
        Mock Get-OpOdtPlan { Get-OdtPlan $Root }
        Mock Save-OpOdt { throw 'Extraction : code retour 5.' }
        $r = Invoke-OpDepotUpdate -Root $tool -Confirm:$false
        $r.OdtUpdated | Should -BeFalse
        $r.ErrorCount | Should -Be 1
        Should -Invoke Invoke-OpDepotPurge -Times 1 -Exactly
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*ODT non mis à jour*code retour 5*' }
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'ODT \[ÉCHEC\]'
    }

    It 'ne télécharge rien quand l''ODT est à jour, compte un plan refusé comme une erreur' {
        $tool = Initialize-TestTool 'u4'
        Mock Get-OpOdtPlan { Get-OdtPlan $Root @{ UpToDate = $true; InstalledVersion = [version]'16.0.20326.20112' } }
        $r = Invoke-OpDepotUpdate -Root $tool -Confirm:$false
        $r.DownloadCount | Should -Be 0
        Should -Invoke Save-OpOdt -Times 0 -Exactly
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'ODT \[à jour\] : setup\.exe 16\.0\.20326\.20112'

        Mock Get-OpOdtPlan { Get-OdtPlan $Root @{ Error = 'Page de l''ODT illisible' } }
        $r = Invoke-OpDepotUpdate -ListOnly -Root $tool
        $r.ErrorCount | Should -Be 1
        (Format-OpDepotPlan -Result $r) -join "`n" | Should -Match 'ODT \[REFUSÉ\] : Page de l''ODT illisible'
    }
}
