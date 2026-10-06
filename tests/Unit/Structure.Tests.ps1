# Arborescence de l'outil (cahier des charges, section 5) et exclusions git.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'Arborescence' {
    It 'a un fichier marqueur offpatch.root lisible, avec un identifiant d''installation' {
        $marker = Get-Content -Path (Join-Path $root 'offpatch.root') -Raw -Encoding UTF8 | ConvertFrom-Json
        $marker.product | Should -Be 'OffPatch'
        $marker.installationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    }

    It 'contient les dossiers de la section 5' {
        foreach ($folder in 'app\module\OffPatch\Public', 'app\module\OffPatch\Private', 'app\gui\Dialogs', 'config\office', 'tools\odt',
            'tests\Unit', 'tests\Fixtures', 'tests\runner', 'docs') {
            Test-Path -Path (Join-Path $root $folder) -PathType Container | Should -BeTrue -Because "$folder fait partie de l'arborescence"
        }
    }

    It 'exclut du dépôt git les données, rapports, journaux, scripts jetables et binaires de tools' {
        $ignore = Get-Content -Path (Join-Path $root '.gitignore') -Encoding UTF8
        foreach ($rule in 'depot/', 'rapports/', 'logs/', 'scratch/', 'tools/**/*.exe') {
            $ignore | Should -Contain $rule
        }
    }
}
