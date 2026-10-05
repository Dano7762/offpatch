# Contrôle Authenticode côté dépôt (cahier des charges 7.1 et 11, R-10) sur des fichiers réels du système :
# powershell.exe est signé par catalogue (Microsoft Windows, racine Microsoft Root Certificate Authority 2010).
# Lecture seule, aucun accès réseau (révocation non contrôlée).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Test-OpFileSignature.ps1')
    $microsoftRoot2010 = '3B1EFD3A66EA28B16697394703A72CA340A05BD5'
    $signedFile = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

Describe 'Test-OpFileSignature' {
    It 'accepte un fichier Microsoft dont la racine figure dans la liste' {
        $r = Test-OpFileSignature -Path $signedFile -TrustedRootThumbprint @($microsoftRoot2010.ToLowerInvariant())
        $r.IsTrusted | Should -BeTrue
        $r.RootThumbprint | Should -Be $microsoftRoot2010
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'refuse une racine absente de la liste, avec son nom et son empreinte' {
        $r = Test-OpFileSignature -Path $signedFile -TrustedRootThumbprint @('0000000000000000000000000000000000000000')
        $r.IsTrusted | Should -BeFalse
        $r.Reason | Should -BeLike "Racine inconnue : CN=Microsoft Root Certificate Authority 2010*$microsoftRoot2010*"
    }

    It 'refuse un fichier non signé' {
        $file = Join-Path $TestDrive 'non-signe.exe'
        [System.IO.File]::WriteAllBytes($file, [byte[]](1..64))
        $r = Test-OpFileSignature -Path $file -TrustedRootThumbprint @($microsoftRoot2010)
        $r.IsTrusted | Should -BeFalse
        $r.Reason | Should -BeLike 'Signature Authenticode non valide*'
    }

    It 'refuse un signataire hors de l''organisation Microsoft Corporation' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Contoso, O=Contoso Ltd, C=US' } }
        }
        $r = Test-OpFileSignature -Path $signedFile -TrustedRootThumbprint @($microsoftRoot2010)
        $r.IsTrusted | Should -BeFalse
        $r.Reason | Should -BeLike '*hors de l''organisation Microsoft Corporation*'
    }
}
