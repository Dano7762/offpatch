# Lecture et validation de la configuration (cahier des charges, 6.1 à 6.4). La configuration réelle du dépôt doit
# être sans anomalie ; chaque altération simulée doit être signalée. Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Test-OpConfiguration', 'Get-OpConfiguration') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    # Une copie neuve de la configuration réelle, à altérer dans chaque test.
    function Get-FreshConfiguration {
        [pscustomobject]@{
            Settings       = Read-OpJsonFile -Path (Join-Path $root 'config\settings.json')
            CatalogQueries = Read-OpJsonFile -Path (Join-Path $root 'config\catalog-queries.json')
            PinnedItems    = Read-OpJsonFile -Path (Join-Path $root 'config\pinned-items.json')
            Profiles       = Read-OpJsonFile -Path (Join-Path $root 'config\office\profiles.json')
        }
    }
}

Describe 'Get-OpConfiguration' {
    It 'charge la configuration réelle du dépôt sans anomalie' {
        $c = Get-OpConfiguration -Root $root
        @($c.Settings.targets).Count | Should -BeGreaterThan 0
        @(Test-OpConfiguration -Configuration $c).Count | Should -Be 0
    }

    It 'liste toutes les anomalies dans une seule erreur' {
        $copy = Join-Path $TestDrive 'outil'
        New-Item -ItemType Directory -Force -Path (Join-Path $copy 'config\office') | Out-Null
        Set-Content -Path (Join-Path $copy 'offpatch.root') -Value '{}' -Encoding UTF8
        foreach ($f in 'settings.json', 'catalog-queries.json', 'pinned-items.json') { Copy-Item (Join-Path $root "config\$f") (Join-Path $copy "config\$f") }
        Copy-Item (Join-Path $root 'config\office\profiles.json') (Join-Path $copy 'config\office\profiles.json')
        $settings = Get-Content (Join-Path $copy 'config\settings.json') -Raw -Encoding UTF8
        $settings = $settings -replace '"level": "INFO"', '"level": "BAVARD"' -replace '"maxAutoReboots": 5', '"maxAutoReboots": 0'
        [IO.File]::WriteAllText((Join-Path $copy 'config\settings.json'), $settings, (New-Object System.Text.UTF8Encoding $false))
        { Get-OpConfiguration -Root $copy } | Should -Throw -ExpectedMessage '*2 anomalie(s)*maxAutoReboots*logging.level*'
    }
}

Describe 'Read-OpJsonFile' {
    It 'nomme le fichier absent' {
        { Read-OpJsonFile -Path (Join-Path $TestDrive 'absent.json') } | Should -Throw -ExpectedMessage '*absent.json*'
    }

    It 'nomme le fichier illisible' {
        $bad = Join-Path $TestDrive 'casse.json'
        Set-Content -Path $bad -Value '{ "a": ' -Encoding UTF8
        { Read-OpJsonFile -Path $bad } | Should -Throw -ExpectedMessage '*illisible*casse.json*'
    }
}

Describe 'Test-OpConfiguration' {
    It 'signale <Attendu>' -TestCases @(
        @{ Attendu = 'une cible sans rétention'; Alter = { param($c) $c.Settings.retention.windowsMonths.PSObject.Properties.Remove('win10-x64') }; Message = '*windowsMonths*win10-x64*' }
        @{ Attendu = 'une cible inconnue'; Alter = { param($c) $c.Settings.targets = @('win11-x64', 'win7-x86') }; Message = '*cible inconnue*win7-x86*' }
        @{ Attendu = 'un domaine avec joker'; Alter = { param($c) $c.Settings.allowedDomains = @($c.Settings.allowedDomains) + '*.microsoft.com' }; Message = "*noms d'hôte exacts*" }
        @{ Attendu = 'un lien downloadPages hors allowedDomains'; Alter = { param($c) $c.Settings.downloadPages.officeDeploymentToolPage = 'https://exemple.net/odt' }; Message = '*exemple.net*allowedDomains*' }
        @{ Attendu = 'un lien downloadPages en http'; Alter = { param($c) $c.Settings.downloadPages.defenderDefinitions.x64 = 'http://go.microsoft.com/fwlink/?LinkID=121721&arch=x64' }; Message = '*non https*' }
        @{ Attendu = 'une empreinte de racine invalide'; Alter = { param($c) $c.Settings.integrity.trustedRootThumbprints = @('1234') }; Message = '*empreinte de racine invalide*' }
        @{ Attendu = 'un point de restauration non booléen'; Alter = { param($c) $c.Settings.client.createRestorePointBeforeSession = 'oui' }; Message = '*createRestorePointBeforeSession*' }
        @{ Attendu = 'une langue Office mal formée'; Alter = { param($c) $c.Settings.office.sources.current.languages = @('français') }; Message = '*langue*français*' }
        @{ Attendu = 'un motif de titre invalide'; Alter = { param($c) $c.CatalogQueries.targets.'win11-x64'[0].includeTitlePattern = '(non fermé' }; Message = '*includeTitlePattern*' }
        @{ Attendu = 'une règle de sélection inconnue'; Alter = { param($c) $c.CatalogQueries.targets.'win11-x64'[0].pick = 'latest' }; Message = '*règle de sélection*latest*' }
        @{ Attendu = 'une dépendance vers une catégorie inconnue'; Alter = { param($c) $c.CatalogQueries.targets.'win10-x64'[0].prerequisites = @('windows-ssu-old') }; Message = '*windows-ssu-old*' }
        @{ Attendu = 'un élément épinglé dont le SHA-1 ne correspond pas au nom'; Alter = { param($c) $c.PinnedItems.items[0].sha1 = ('0' * 40) }; Message = "*empreinte du nom de fichier*" }
        @{ Attendu = 'un élément épinglé hors allowedDomains'; Alter = { param($c) $c.PinnedItems.items[0].url = 'https://exemple.net/a_' + $c.PinnedItems.items[0].sha1 + '.msu' }; Message = '*hôte du lien*' }
        @{ Attendu = 'une clé acceptée pour une licence de détail'; Alter = { param($c) $c.Profiles.profiles[0].acceptsProductKey = $true }; Message = '*licence en volume*' }
        @{ Attendu = 'un profil sur une source non déclarée'; Alter = { param($c) $c.Profiles.profiles[0].source = 'monthlyenterprise' }; Message = '*monthlyenterprise*' }
    ) {
        param($Attendu, $Alter, $Message)
        $c = Get-FreshConfiguration
        & $Alter $c
        $errors = @(Test-OpConfiguration -Configuration $c)
        $errors.Count | Should -BeGreaterThan 0 -Because "l'anomalie « $Attendu » doit être signalée"
        ($errors -join ' | ') | Should -BeLike $Message
    }
}
