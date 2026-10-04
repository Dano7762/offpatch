# Cohérence de config/pinned-items.json (éléments épinglés, cahier des charges 6.4). Aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $config = Get-Content -Path (Join-Path $root 'config\pinned-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @($config.items | ForEach-Object { @{ Item = $_; Id = $_.id } })
}

Describe 'Élément épinglé <Id>' -ForEach $items {
    It 'a tous les champs attendus' {
        foreach ($field in 'id', 'category', 'kb', 'arch', 'url', 'sha1', 'appliesToBaseBuilds') {
            $Item.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty -Because "le champ $field est obligatoire"
        }
    }

    It 'pointe en HTTPS vers un domaine de fichiers du catalogue' {
        $uri = [uri]$Item.url
        $uri.Scheme | Should -Be 'https'
        $uri.Host | Should -BeIn @('catalog.sf.dl.delivery.mp.microsoft.com', 'catalog.s.download.windowsupdate.com')
    }

    It 'a un SHA-1 identique à l''empreinte du nom de fichier' {
        $fromName = [regex]::Match(([uri]$Item.url).Segments[-1], '_([0-9a-fA-F]{40})\.msu$').Groups[1].Value.ToLowerInvariant()
        $Item.sha1 | Should -Match '^[0-9a-f]{40}$'
        $Item.sha1 | Should -Be $fromName
    }

    It 'a un nom de fichier qui correspond à son architecture, et à son KB quand le nom en porte un' {
        $name = ([uri]$Item.url).Segments[-1]
        $name | Should -Match ('(?i)-{0}_[0-9a-f]{{40}}\.msu$' -f $Item.arch)
        if ($name -match '(?i)-kb\d+-') { $name | Should -Match ('(?i)-{0}-' -f $Item.kb) }
    }
}
