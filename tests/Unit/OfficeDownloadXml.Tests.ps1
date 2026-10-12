# Génération des XML de téléchargement de l'ODT par source et langues (cahier des charges 6.3, 7.1) : modèle
# config\office\download.xml.template rempli depuis office\sources.json. Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Get-OpRoot', 'Get-OpPath', 'Read-OpJsonFile', 'Test-OpConfiguration', 'Get-OpConfiguration', 'Get-OpOfficeDownloadXml') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    # Copie de l'outil sous un chemin à caractères spéciaux (accent, esperluette), comme un support réel.
    $script:tool = Join-Path $TestDrive 'Mises à jour & co'
    New-Item -ItemType Directory -Force -Path $script:tool | Out-Null
    Copy-Item -Path (Join-Path $root 'config') -Destination $script:tool -Recurse
    Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $script:tool
    $script:configuration = Get-OpConfiguration -Root $script:tool
    $script:result = @(Get-OpOfficeDownloadXml -Configuration $script:configuration -Root $script:tool)
}

Describe 'Get-OpOfficeDownloadXml' {
    It 'renvoie un XML par source configurée' {
        $script:result.Id | Should -Be @($script:configuration.OfficeSources.sources.id)
    }

    It 'remplit canal, produit, langues et chemin absolu de la source dans le dépôt' {
        foreach ($src in @($script:configuration.OfficeSources.sources)) {
            $r = $script:result | Where-Object Id -EQ $src.id
            $expectedPath = Join-Path $script:tool ('depot\' + ($src.folder -replace '/', '\'))
            $r.SourcePath | Should -Be $expectedPath
            $x = [xml]$r.Xml
            $x.Configuration.Add.SourcePath | Should -Be $expectedPath
            $x.Configuration.Add.Channel | Should -Be $src.channel
            $x.Configuration.Add.OfficeClientEdition | Should -Be '64'
            @($x.Configuration.Add.Product).Count | Should -Be 1
            $x.Configuration.Add.Product.ID | Should -Be $src.downloadProductId
            @($x.Configuration.Add.Product.Language | ForEach-Object { $_.ID }) | Should -Be @($src.languages)
            $r.Languages | Should -Be @($src.languages)
        }
    }

    It 'ne contient ni clé, ni Remove, ni version imposée, ni lien de secours' {
        foreach ($r in $script:result) {
            $r.Xml | Should -Not -Match 'PIDKEY|<Remove|Version=|AllowCdnFallback|\{\{'
        }
    }

    It 'échappe le chemin pour XML' {
        $script:result[0].Xml | Should -Match 'Mises à jour &amp; co'
    }

    It 'refuse un modèle qui ne donne pas un XML valide' {
        $broken = Join-Path $TestDrive 'casse'
        Copy-Item -Path $script:tool -Destination $broken -Recurse
        Set-Content -LiteralPath (Join-Path $broken 'config\office\download.xml.template') -Value '<Configuration><Add>' -Encoding UTF8
        { Get-OpOfficeDownloadXml -Configuration $script:configuration -Root $broken } | Should -Throw -ExpectedMessage '*source current invalide*'
    }
}
