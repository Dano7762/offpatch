# Résolution des redirections et contrôle des hôtes (cahier des charges 6.1, 7.1, 11 ; R-13).
# Requêtes HEAD simulées : aucun accès réseau.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Invoke-OpHeadRequest.ps1')
    . (Join-Path $root 'app\module\OffPatch\Private\Resolve-OpDownloadUrl.ps1')
    $allowed = @((Get-Content -Path (Join-Path $root 'config\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json).allowedDomains)
}

Describe 'Resolve-OpDownloadUrl' {
    It 'renvoie le lien tel quel quand le serveur répond 200 sans redirection' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 200; Location = $null } }
        $r = Resolve-OpDownloadUrl -Url 'https://catalog.sf.dl.delivery.mp.microsoft.com/files/a.msu' -AllowedDomain $allowed
        $r.Url | Should -Be 'https://catalog.sf.dl.delivery.mp.microsoft.com/files/a.msu'
        @($r.Hosts) | Should -Be @('catalog.sf.dl.delivery.mp.microsoft.com')
    }

    It 'suit la chaîne de mpam-fe.exe et contrôle chaque hôte' {
        Mock Invoke-OpHeadRequest {
            switch -Wildcard ($Url) {
                'https://go.microsoft.com/*' { [pscustomobject]@{ StatusCode = 302; Location = 'https://definitionupdates.microsoft.com/download/DefinitionUpdates/versionedsignatures/am/1.1/x64/mpam-fe.exe' } }
                default { [pscustomobject]@{ StatusCode = 200; Location = $null } }
            }
        }
        $r = Resolve-OpDownloadUrl -Url 'https://go.microsoft.com/fwlink/?LinkID=121721&arch=x64' -AllowedDomain $allowed
        $r.Url | Should -BeLike 'https://definitionupdates.microsoft.com/*'
        @($r.Hosts) | Should -Be @('go.microsoft.com', 'definitionupdates.microsoft.com')
    }

    It 'refuse une redirection vers un hôte absent de la liste, avec l''hôte, l''URL et la ligne à ajouter' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 302; Location = 'https://cdn.exemple.net/fichier.exe' } }
        { Resolve-OpDownloadUrl -Url 'https://go.microsoft.com/fwlink/?LinkID=1' -AllowedDomain $allowed } |
            Should -Throw -ExpectedMessage '*Hôte non autorisé : cdn.exemple.net. URL : https://cdn.exemple.net/fichier.exe.*"cdn.exemple.net",*'
    }

    It 'refuse un hôte proche d''un hôte autorisé (nom exact, pas de suffixe)' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 200; Location = $null } }
        { Resolve-OpDownloadUrl -Url 'https://evil.download.microsoft.com/a.exe' -AllowedDomain $allowed } | Should -Throw -ExpectedMessage '*Hôte non autorisé : evil.download.microsoft.com*'
        { Resolve-OpDownloadUrl -Url 'https://catalog.update.microsoft.com/a' -AllowedDomain $allowed } | Should -Throw -ExpectedMessage '*Hôte non autorisé*'
        Should -Invoke Invoke-OpHeadRequest -Times 0 -Exactly
    }

    It 'réécrit un lien http en https sur le même hôte et ne demande jamais rien en http' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 200; Location = $null } }
        $r = Resolve-OpDownloadUrl -Url 'http://catalog.s.download.windowsupdate.com/c/msdownload/a.msu' -AllowedDomain $allowed
        $r.Url | Should -Be 'https://catalog.s.download.windowsupdate.com/c/msdownload/a.msu'
        Should -Invoke Invoke-OpHeadRequest -Times 0 -Exactly -ParameterFilter { $Url -like 'http:*' }
    }

    It 'réécrit aussi en https une redirection http' {
        Mock Invoke-OpHeadRequest {
            if ($Url -like 'https://go.microsoft.com/*') { [pscustomobject]@{ StatusCode = 301; Location = 'http://download.microsoft.com/a.exe' } }
            else { [pscustomobject]@{ StatusCode = 200; Location = $null } }
        }
        (Resolve-OpDownloadUrl -Url 'https://go.microsoft.com/fwlink/?LinkID=2' -AllowedDomain $allowed).Url | Should -Be 'https://download.microsoft.com/a.exe'
    }

    It 'résout une redirection relative sur le même hôte' {
        Mock Invoke-OpHeadRequest {
            if ($Url -like '*/ancien*') { [pscustomobject]@{ StatusCode = 302; Location = '/nouveau/a.exe' } }
            else { [pscustomobject]@{ StatusCode = 200; Location = $null } }
        }
        (Resolve-OpDownloadUrl -Url 'https://download.microsoft.com/ancien/a.exe' -AllowedDomain $allowed).Url | Should -Be 'https://download.microsoft.com/nouveau/a.exe'
    }

    It 'refuse une boucle de redirections' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 302; Location = 'https://go.microsoft.com/fwlink/?LinkID=3' } }
        { Resolve-OpDownloadUrl -Url 'https://go.microsoft.com/fwlink/?LinkID=3' -AllowedDomain $allowed -MaxRedirects 3 } | Should -Throw -ExpectedMessage '*Plus de 3 redirections*'
    }

    It 'refuse un code final d''erreur' {
        Mock Invoke-OpHeadRequest { [pscustomobject]@{ StatusCode = 404; Location = $null } }
        { Resolve-OpDownloadUrl -Url 'https://download.microsoft.com/absent.exe' -AllowedDomain $allowed } | Should -Throw -ExpectedMessage '*HTTP 404*'
    }

    It 'refuse un schéma autre que http ou https' {
        { Resolve-OpDownloadUrl -Url 'ftp://download.microsoft.com/a.exe' -AllowedDomain $allowed } | Should -Throw -ExpectedMessage '*schéma ftp*'
    }
}
