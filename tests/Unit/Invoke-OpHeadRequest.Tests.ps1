# Requête HEAD sans redirection automatique (Resolve-OpDownloadUrl, R-13), contre un petit serveur HTTP local
# (HttpListener sur localhost, sans droits d'administrateur) : redirection rendue telle quelle, taille annoncée,
# nouvelles tentatives sur 503, échec immédiat sur 404, erreur explicite sans réponse.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Invoke-OpHeadRequest.ps1')
}

Describe 'Invoke-OpHeadRequest (serveur local)' {
    BeforeAll {
        $script:port = Get-Random -Minimum 20000 -Maximum 40000
        $script:base = "http://localhost:$($script:port)"
        $script:requests = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("$($script:base)/")
        $listener.Start()
        $script:listener = $listener
        $script:server = [powershell]::Create()
        $null = $script:server.AddScript({
                param($Listener, $Requests)
                $flaky = 0
                while ($Listener.IsListening) {
                    try { $context = $Listener.GetContext() } catch { break }
                    $request = $context.Request
                    $response = $context.Response
                    $Requests.Enqueue("$($request.HttpMethod) $($request.Url.AbsolutePath)")
                    switch ($request.Url.AbsolutePath) {
                        '/redirect' { $response.StatusCode = 302; $response.RedirectLocation = 'https://definitionupdates.microsoft.com/mpam-fe.exe' }
                        '/absent' { $response.StatusCode = 404 }
                        '/flaky' {
                            $flaky++
                            if ($flaky -eq 1) { $response.StatusCode = 503 } else { $response.ContentLength64 = 1234 }
                        }
                        '/down' { $response.StatusCode = 503 }
                        default { $response.ContentLength64 = 4321 }
                    }
                    $response.Close()
                }
            }).AddArgument($listener).AddArgument($script:requests)
        $script:handle = $script:server.BeginInvoke()
        function Get-RequestList { $r = $null; $all = @(); while ($script:requests.TryDequeue([ref]$r)) { $all += $r }; $all }
    }

    AfterAll {
        $script:listener.Stop()
        $script:listener.Close()
        $script:server.Stop()
        $script:server.Dispose()
    }

    BeforeEach { $null = Get-RequestList }

    It 'envoie une requête HEAD et renvoie la taille annoncée' {
        $r = Invoke-OpHeadRequest -Url "$($script:base)/fichier.msu" -DelaySeconds 0
        $r.StatusCode | Should -Be 200
        $r.ContentLength | Should -Be 4321
        $r.Location | Should -BeNullOrEmpty
        Get-RequestList | Should -Be @('HEAD /fichier.msu')
    }

    It 'rend la redirection sans la suivre' {
        $r = Invoke-OpHeadRequest -Url "$($script:base)/redirect" -DelaySeconds 0
        $r.StatusCode | Should -Be 302
        $r.Location | Should -Be 'https://definitionupdates.microsoft.com/mpam-fe.exe'
        Get-RequestList | Should -Be @('HEAD /redirect')
    }

    It 'retente après une erreur 503, puis renvoie la réponse suivante' {
        $r = Invoke-OpHeadRequest -Url "$($script:base)/flaky" -DelaySeconds 0
        $r.StatusCode | Should -Be 200
        $r.ContentLength | Should -Be 1234
        @(Get-RequestList).Count | Should -Be 2
    }

    It 'renvoie le dernier code reçu quand l''erreur passagère persiste' {
        $r = Invoke-OpHeadRequest -Url "$($script:base)/down" -MaxAttempts 3 -DelaySeconds 0
        $r.StatusCode | Should -Be 503
        @(Get-RequestList).Count | Should -Be 3
    }

    It 'renvoie une erreur 404 tout de suite, sans nouvelle tentative' {
        $r = Invoke-OpHeadRequest -Url "$($script:base)/absent" -DelaySeconds 0
        $r.StatusCode | Should -Be 404
        @(Get-RequestList).Count | Should -Be 1
    }

    It 'lève une erreur qui donne l''URL quand aucun serveur ne répond' {
        # 127.0.0.1 plutôt que localhost : refus immédiat, sans essai IPv6 puis IPv4 à chaque tentative.
        $closed = "http://127.0.0.1:$($script:port + 1)/fichier.msu"
        { Invoke-OpHeadRequest -Url $closed -MaxAttempts 2 -DelaySeconds 0 } | Should -Throw "*sans réponse après 2 tentative(s), URL $closed*"
    }
}
