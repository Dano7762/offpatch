# Mise à jour du dépôt de bout en bout (cahier des charges 7.1 à 7.3), réseau simulé à ses seules frontières :
# pages du catalogue (Invoke-OpWebRequest, pages réelles de tests/Fixtures/catalog), requêtes HEAD
# (Invoke-OpHeadRequest) et transfert BITS (Invoke-OpBitsDownload). Tout le reste tourne pour de vrai : sélection,
# fenêtre de téléchargement, contrôle des hôtes, dossier temporaire, rangement, manifeste, purge. Seuls le contrôle
# de signature et de SHA-1, la version du fichier et la lecture du .msu sont simulés : les fichiers écrits ici ne sont
# pas de vrais fichiers Microsoft.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }
    $fixtures = Join-Path $root 'tests\Fixtures\catalog'
    $script:search = [System.IO.File]::ReadAllText((Join-Path $fixtures 'search-kb5129195.html'))
    $script:noResult = [System.IO.File]::ReadAllText((Join-Path $fixtures 'search-noresult.html'))
    $script:dialog = [System.IO.File]::ReadAllText((Join-Path $fixtures 'dialog-kb5129195.html'))
    $script:defenderUrl = 'https://definitionupdates.microsoft.com/packages/content/mpam-fe.exe?packageType=Signatures&packageVersion=1.459.675.0&arch=amd64&engineVersion=1.1.26080.3'
    $script:now = [datetime]'2026-09-20'

    # Outil de test réduit à la cible win11-x64 (la fenêtre enregistrée est celle de la cumulative x64).
    function Initialize-TestTool([string]$Name) {
        $tool = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path $tool | Out-Null
        Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
        Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
        $path = Join-Path $tool 'config\settings.json'
        $settings = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $settings.targets = @('win11-x64')
        [System.IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        $tool
    }
    function Get-Manifest([string]$Tool) { Get-Content -Path (Join-Path $Tool 'depot\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
    # Contenu propre à chaque lien (64 octets), pour que chaque fichier ait son SHA-256.
    function Get-FakeContent([string]$Url) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Url)) } finally { $sha.Dispose() }
        [byte[]]($h + $h)
    }
}

Describe 'Invoke-OpDepotUpdate, réseau simulé' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Get-OpOdtPlan {} # ODT : Odt.Tests.ps1
        Mock Invoke-OpWebRequest {
            if ($Uri -like '*/DownloadDialog.aspx') { return $script:dialog }
            if ($Uri -like '*/Search.aspx?q=*Cumulative%20Update%20for%20Windows%2011*') { return $script:search }
            $script:noResult
        }
        Mock Invoke-OpHeadRequest {
            if (([uri]$Url).Host -eq 'go.microsoft.com') { return [pscustomobject]@{ StatusCode = 302; Location = $script:defenderUrl; ContentLength = $null } }
            [pscustomobject]@{ StatusCode = 200; Location = $null; ContentLength = [int64]64 }
        }
        Mock Invoke-OpBitsDownload {
            [System.IO.File]::WriteAllBytes($Destination, (Get-FakeContent $Url))
            [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $false; SizeBytes = [long]64 }
        }
        Mock Invoke-OpHttpDownload { throw 'ne doit pas être appelé' }
        Mock Confirm-OpDownloadIntegrity {
            [pscustomobject]@{ Path = $Path; Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant(); Sha1 = $ExpectedSha1; Signer = 'O=Microsoft Corporation'; RootThumbprint = $TrustedRootThumbprint[0] }
        }
        Mock Get-OpFileVersion { [version]'1.459.675.0' }
        Mock Read-OpMsuPackage { [pscustomobject]@{ name = 'Package_for_RollupFix'; version = '26100.9457.1.0' } }
    }

    It 'sélectionne, télécharge et range la cumulative, sa checkpoint, l''enablement package et les définitions Defender' {
        $tool = Initialize-TestTool 'd1'
        $r = Invoke-OpDepotUpdate -Root $tool -Now $script:now

        $r.ErrorCount | Should -Be 0
        @($r.NewItems | ForEach-Object { $_.id } | Sort-Object) | Should -Be @('win11-x64-checkpoint-KB5043080', 'win11-x64-defender-1.459.675.0', 'win11-x64-ekb-26H2', 'win11-x64-lcu-KB5129195')
        # Une recherche par version et par mois (2 x 3), puis les catégories sans résultat ; une seule fenêtre.
        Should -Invoke Invoke-OpWebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/DownloadDialog.aspx' }
        Should -Invoke Invoke-OpWebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*q=2026-08%20Cumulative%20Update%20for%20Windows%2011%2C%20version%2025H2' }
        # Les définitions sont téléchargées depuis l'URL finale, jamais depuis le lien de redirection.
        Should -Invoke Invoke-OpBitsDownload -Times 4 -Exactly
        Should -Invoke Invoke-OpBitsDownload -Times 1 -Exactly -ParameterFilter { $Url -eq $script:defenderUrl }
        Should -Invoke Invoke-OpBitsDownload -Times 0 -Exactly -ParameterFilter { ([uri]$Url).Host -eq 'go.microsoft.com' }

        $m = Get-Manifest $tool
        @(Test-OpManifest -Manifest $m) | Should -BeNullOrEmpty
        foreach ($item in @($m.items)) {
            foreach ($f in @($item.files)) { Join-Path $tool "depot\$($f.path)" | Should -Exist }
        }
        $lcu = @($m.items | Where-Object { $_.id -eq 'win11-x64-lcu-KB5129195' })[0]
        $lcu.resultingUbr | Should -Be 9457
        @($lcu.files)[0].package.name | Should -Be 'Package_for_RollupFix'
        @(Get-ChildItem -Path (Join-Path $tool 'depot\.tmp') -Recurse -File -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        @($r.Purge.RemovedItems).Count | Should -Be 0
        @($r.Purge.Orphans).Count | Should -Be 0
    }

    It 'ne retélécharge rien au second passage et annonce un dépôt à jour' {
        $tool = Initialize-TestTool 'd2'
        Invoke-OpDepotUpdate -Root $tool -Now $script:now | Out-Null
        $r = Invoke-OpDepotUpdate -Root $tool -Now $script:now

        Should -Invoke Invoke-OpBitsDownload -Times 4 -Exactly
        @($r.NewItems).Count | Should -Be 0
        $r.ErrorCount | Should -Be 0
        $r.DownloadCount | Should -Be 0
        @((Get-Manifest $tool).items).Count | Should -Be 4
    }

    It 'refuse une redirection vers un hôte non autorisé sans rien demander à cet hôte, et inscrit les autres éléments' {
        $tool = Initialize-TestTool 'd3'
        Mock Invoke-OpHeadRequest {
            if ($Url -like '*kb5043080*') { return [pscustomobject]@{ StatusCode = 302; Location = 'https://cdn.exemple.net/kb5043080.msu'; ContentLength = $null } }
            if (([uri]$Url).Host -eq 'go.microsoft.com') { return [pscustomobject]@{ StatusCode = 302; Location = $script:defenderUrl; ContentLength = $null } }
            [pscustomobject]@{ StatusCode = 200; Location = $null; ContentLength = [int64]64 }
        }
        $r = Invoke-OpDepotUpdate -Root $tool -Now $script:now

        $r.ErrorCount | Should -Be 2
        @($r.NewItems | ForEach-Object { $_.id }) | Should -Not -Contain 'win11-x64-checkpoint-KB5043080'
        @($r.NewItems).Count | Should -Be 3
        Should -Invoke Invoke-OpHeadRequest -Times 0 -Exactly -ParameterFilter { ([uri]$Url).Host -eq 'cdn.exemple.net' }
        Should -Invoke Invoke-OpBitsDownload -Times 0 -Exactly -ParameterFilter { $Url -like '*exemple.net*' }
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*cdn.exemple.net*' }
    }

    It 'garde un fichier dont la taille reçue diffère de la taille annoncée hors du dépôt' {
        $tool = Initialize-TestTool 'd4'
        Mock Invoke-OpBitsDownload {
            [byte[]]$content = Get-FakeContent $Url
            if ($Url -like '*kb5129195*') { $content = $content[0..9] }
            [System.IO.File]::WriteAllBytes($Destination, $content)
            [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $false; SizeBytes = [long]$content.Length }
        }
        $r = Invoke-OpDepotUpdate -Root $tool -Now $script:now

        @($r.NewItems | ForEach-Object { $_.id }) | Should -Not -Contain 'win11-x64-lcu-KB5129195'
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*10 octet(s) reçus, 64 attendus*' }
        @(Get-ChildItem -Path (Join-Path $tool 'depot') -Recurse -File -Filter 'windows11.0-kb5129195*') | Should -BeNullOrEmpty
    }

    It 'journalise et relance une erreur du catalogue, sans rien télécharger ni écrire au manifeste' {
        $tool = Initialize-TestTool 'd5'
        Mock Invoke-OpWebRequest { throw 'Requête en échec après 3 tentative(s) : HTTP 503' }

        { Invoke-OpDepotUpdate -Root $tool -Now $script:now } | Should -Throw '*HTTP 503*'
        Should -Invoke Invoke-OpBitsDownload -Times 0 -Exactly
        Join-Path $tool 'depot\manifest.json' | Should -Not -Exist
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'ERROR' -and $Message -like '*interrompue*HTTP 503*' }
    }
}
