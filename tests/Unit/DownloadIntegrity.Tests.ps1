# Contrôle d'un fichier reçu dans le dossier temporaire du dépôt (cahier des charges 7.1 et 11, R-10) : signature
# Authenticode, SHA-1 publié, SHA-256 calculé. Signature réelle sur un fichier du système (lecture seule), simulée
# par un mock pour les fichiers écrits dans TestDrive.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Write-OpLog', 'ConvertTo-OpMaskedText', 'Test-OpFileSignature', 'Confirm-OpDownloadIntegrity') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $microsoftRoot2010 = '3B1EFD3A66EA28B16697394703A72CA340A05BD5'
    $signedFile = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    function Write-TestFile([string]$Name, [int]$Size) {
        $path = Join-Path $TestDrive $Name
        $bytes = New-Object byte[] $Size
        for ($i = 0; $i -lt $Size; $i++) { $bytes[$i] = [byte](($i * 13) % 251) }
        [System.IO.File]::WriteAllBytes($path, $bytes)
        $path
    }

    # Référence indépendante de la fonction testée (Get-FileHash -Algorithm SHA1 est signalé par l'analyse statique).
    function Get-Sha1Hex([string]$Path) {
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        try { -join ($sha1.ComputeHash([System.IO.File]::ReadAllBytes($Path)) | ForEach-Object { $_.ToString('x2') }) } finally { $sha1.Dispose() }
    }
}

Describe 'Confirm-OpDownloadIntegrity' {
    It 'accepte un fichier Microsoft signé et calcule ses empreintes' {
        $r = Confirm-OpDownloadIntegrity -Path $signedFile -TrustedRootThumbprint @($microsoftRoot2010)
        $r.Sha256 | Should -Be (Get-FileHash -LiteralPath $signedFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $r.Sha1 | Should -Be (Get-Sha1Hex $signedFile)
        $r.RootThumbprint | Should -Be $microsoftRoot2010
        $r.Signer | Should -Match 'O=Microsoft Corporation'
    }

    Context 'signature simulée valide' {
        BeforeAll {
            Mock Test-OpFileSignature { [pscustomobject]@{ IsTrusted = $true; Signer = 'CN=Microsoft Corporation, O=Microsoft Corporation'; RootThumbprint = $microsoftRoot2010; Reason = $null } }
        }

        It 'calcule les empreintes d''un fichier de plusieurs blocs de lecture' {
            $file = Write-TestFile -Name 'gros.msu' -Size (2MB + 12345)
            $sha1 = Get-Sha1Hex $file
            $r = Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010) -ExpectedSha1 $sha1.ToUpperInvariant()
            $r.Sha256 | Should -Be (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            $r.Sha1 | Should -Be $sha1
            Test-Path -LiteralPath $file | Should -BeTrue
        }

        It 'calcule les empreintes d''un fichier vide' {
            $file = Write-TestFile -Name 'vide.cab' -Size 0
            (Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010)).Sha256 |
                Should -Be 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        }

        It 'refuse et supprime un fichier dont le SHA-1 diffère de l''empreinte publiée' {
            $file = Write-TestFile -Name 'altere.msu' -Size 4096
            { Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010) -ExpectedSha1 ('0' * 40) } |
                Should -Throw "Fichier refusé, altere.msu : SHA-1 * différent de l'empreinte publiée $('0' * 40)."
            Test-Path -LiteralPath $file | Should -BeFalse
        }

        It 'respecte -WhatIf : fichier refusé conservé' {
            $file = Write-TestFile -Name 'whatif.msu' -Size 16
            { Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010) -ExpectedSha1 ('0' * 40) -WhatIf } | Should -Throw
            Test-Path -LiteralPath $file | Should -BeTrue
        }
    }

    It 'refuse et supprime un fichier non signé, avec la raison de Test-OpFileSignature' {
        $file = Write-TestFile -Name 'non-signe.exe' -Size 64
        { Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010) } |
            Should -Throw 'Fichier refusé, non-signe.exe : Signature Authenticode non valide*'
        Test-Path -LiteralPath $file | Should -BeFalse
    }

    It 'refuse et supprime un fichier dont la racine est inconnue' {
        $file = Join-Path $TestDrive 'racine.exe'
        Copy-Item -LiteralPath $signedFile -Destination $file
        Mock Test-OpFileSignature { [pscustomobject]@{ IsTrusted = $false; Reason = 'Racine inconnue : CN=Autre (empreinte 00). Téléchargement refusé.' } }
        { Confirm-OpDownloadIntegrity -Path $file -TrustedRootThumbprint @($microsoftRoot2010) } |
            Should -Throw 'Fichier refusé, racine.exe : Racine inconnue : CN=Autre*'
        Test-Path -LiteralPath $file | Should -BeFalse
    }
}
