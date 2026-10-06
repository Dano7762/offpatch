# Politique de nouvelles tentatives des requêtes web (pages du catalogue, page de l'ODT). Réseau simulé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Invoke-OpWebRequest.ps1')
    function Get-SimulatedHttpError([int]$StatusCode, [string]$Content) {
        $exception = New-Object System.Exception "Erreur HTTP $StatusCode simulée"
        $response = [pscustomobject]@{ StatusCode = $StatusCode; Content = $Content }
        $response | Add-Member -MemberType ScriptMethod -Name GetResponseStream -Value { New-Object System.IO.MemoryStream (, [Text.Encoding]::UTF8.GetBytes($this.Content)) }
        $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
        $exception
    }
}

Describe 'Invoke-OpWebRequest' {
    BeforeEach { Mock Start-Sleep { } }

    It 'renvoie le contenu dès la première réponse' {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = '<html>ok</html>' } }
        Invoke-OpWebRequest -Uri 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB1' | Should -Be '<html>ok</html>'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'retente après une erreur réseau, puis réussit' {
        $script:calls = 0
        Mock Invoke-WebRequest {
            $script:calls++
            if ($script:calls -lt 3) { throw (New-Object System.Net.WebException 'Délai dépassé') }
            [pscustomobject]@{ Content = 'page' }
        }
        Invoke-OpWebRequest -Uri 'https://www.catalog.update.microsoft.com/' -DelaySeconds 1 | Should -Be 'page'
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'retente sur un HTTP 503 et donne le code, l''URL et un extrait après la dernière tentative' {
        Mock Invoke-WebRequest { throw (Get-SimulatedHttpError -StatusCode 503 -Content '<html><body>Service Unavailable, maintenance en cours</body></html>') }
        { Invoke-OpWebRequest -Uri 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB2' -MaxAttempts 2 } |
            Should -Throw -ExpectedMessage '*2 tentative(s) : HTTP 503, URL https://www.catalog.update.microsoft.com/Search.aspx?q=KB2*Service Unavailable, maintenance en cours*'
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
    }

    It 'ne retente pas sur un HTTP 404' {
        Mock Invoke-WebRequest { throw (Get-SimulatedHttpError -StatusCode 404 -Content 'introuvable') }
        { Invoke-OpWebRequest -Uri 'https://www.catalog.update.microsoft.com/absent' } | Should -Throw -ExpectedMessage '*1 tentative(s) : HTTP 404*'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
}
