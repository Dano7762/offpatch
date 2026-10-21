# Téléchargement dans le dossier temporaire du dépôt (cahier des charges 7.1, R-16) : BITS simulé (cmdlets BitsTransfer
# remplacées par des mocks), repli HttpClient testé contre un petit serveur HTTP local (HttpListener sur localhost, sans
# droits d'administrateur) qui gère les plages d'octets, l'absence de reprise, une redirection et une erreur 404.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'Write-OpLog', 'Write-OpProgress', 'Format-OpSize', 'ConvertTo-OpMaskedText', 'Assert-OpNotCancelled', 'Invoke-OpBitsDownload', 'Invoke-OpHttpDownload', 'Save-OpDownload') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    Import-Module -Name BitsTransfer -Verbose:$false
}

Describe 'Invoke-OpHttpDownload (serveur local)' {
    BeforeAll {
        # Contenu de 3 Mio reconnaissable octet par octet.
        $script:content = New-Object byte[] (3MB)
        for ($i = 0; $i -lt $script:content.Length; $i++) { $script:content[$i] = [byte](($i * 7) % 251) }
        $script:port = Get-Random -Minimum 20000 -Maximum 40000
        $script:base = "http://localhost:$($script:port)"
        $script:requests = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("$($script:base)/")
        $listener.Start()
        $script:listener = $listener
        $script:server = [powershell]::Create()
        $null = $script:server.AddScript({
                param($Listener, $Content, $Requests)
                while ($Listener.IsListening) {
                    try { $context = $Listener.GetContext() } catch { break }
                    $request = $context.Request
                    $response = $context.Response
                    $range = $request.Headers['Range']
                    $Requests.Enqueue("$($request.Url.AbsolutePath)|$range")
                    switch ($request.Url.AbsolutePath) {
                        '/redirect' { $response.StatusCode = 302; $response.RedirectLocation = 'https://exemple.net/fichier' ; $response.Close() }
                        '/absent' { $response.StatusCode = 404; $response.Close() }
                        default {
                            $start = 0
                            if ($request.Url.AbsolutePath -eq '/range' -and $range -match '^bytes=(\d+)-$') {
                                $start = [int]$Matches[1]
                                $response.StatusCode = 206
                                $response.AddHeader('Content-Range', "bytes $start-$($Content.Length - 1)/$($Content.Length)")
                            }
                            $response.ContentLength64 = $Content.Length - $start
                            $response.OutputStream.Write($Content, $start, $Content.Length - $start)
                            $response.Close()
                        }
                    }
                }
            }).AddArgument($listener).AddArgument($script:content).AddArgument($script:requests)
        $script:handle = $script:server.BeginInvoke()
        Mock Write-OpLog {}
        function Get-LastRange { $r = $null; $last = $null; while ($script:requests.TryDequeue([ref]$r)) { $last = $r }; $last }
    }

    AfterAll {
        $script:listener.Stop()
        $script:listener.Close()
        $script:server.Stop()
        $script:server.Dispose()
    }

    It 'télécharge le fichier complet et renomme le fichier partiel' {
        $dest = Join-Path $TestDrive 'complet.bin'
        $r = Invoke-OpHttpDownload -Url "$($script:base)/range" -Destination $dest
        $r.Engine | Should -Be 'HttpClient'
        $r.Resumed | Should -BeFalse
        [System.IO.File]::ReadAllBytes($dest).Length | Should -Be $script:content.Length
        Test-Path "$dest.part" | Should -BeFalse
        Get-LastRange | Should -Be '/range|'
    }

    It 'reprend un fichier partiel par un en-tête Range et produit le contenu exact' {
        $dest = Join-Path $TestDrive 'repris.bin'
        $head = New-Object byte[] (1MB)
        [Array]::Copy($script:content, $head, $head.Length)
        [System.IO.File]::WriteAllBytes("$dest.part", $head)
        $r = Invoke-OpHttpDownload -Url "$($script:base)/range" -Destination $dest
        $r.Resumed | Should -BeTrue
        Get-LastRange | Should -Be "/range|bytes=$(1MB)-"
        $bytes = [System.IO.File]::ReadAllBytes($dest)
        $bytes.Length | Should -Be $script:content.Length
        [Convert]::ToBase64String((New-Object Security.Cryptography.SHA256Managed).ComputeHash($bytes)) |
            Should -Be ([Convert]::ToBase64String((New-Object Security.Cryptography.SHA256Managed).ComputeHash($script:content)))
    }

    It 'reprend de zéro quand le serveur ignore la plage demandée (HTTP 200)' {
        $dest = Join-Path $TestDrive 'sansrange.bin'
        [System.IO.File]::WriteAllBytes("$dest.part", (New-Object byte[] 1000))
        $r = Invoke-OpHttpDownload -Url "$($script:base)/norange" -Destination $dest
        $r.Resumed | Should -BeFalse
        [System.IO.File]::ReadAllBytes($dest).Length | Should -Be $script:content.Length
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*ignore la reprise*' }
    }

    It 'refuse une redirection sans créer de fichier' {
        $dest = Join-Path $TestDrive 'redirige.bin'
        { Invoke-OpHttpDownload -Url "$($script:base)/redirect" -Destination $dest } | Should -Throw -ExpectedMessage '*redirection HTTP 302*exemple.net*'
        Test-Path $dest | Should -BeFalse
        Test-Path "$dest.part" | Should -BeFalse
    }

    It 'lève une erreur sur un code HTTP d''échec et garde le fichier partiel pour la reprise' {
        $dest = Join-Path $TestDrive 'absent.bin'
        [System.IO.File]::WriteAllBytes("$dest.part", (New-Object byte[] 10))
        { Invoke-OpHttpDownload -Url "$($script:base)/absent" -Destination $dest } | Should -Throw -ExpectedMessage '*HTTP 404*'
        (Get-Item "$dest.part").Length | Should -Be 10
    }

    It 's''arrête à la demande d''annulation et garde le fichier partiel pour la reprise' {
        $dest = Join-Path $TestDrive 'annule.bin'
        $source = New-Object System.Threading.CancellationTokenSource
        $source.Cancel()
        $script:OpCancellation = $source.Token
        try {
            { Invoke-OpHttpDownload -Url "$($script:base)/range" -Destination $dest } | Should -Throw -ExceptionType ([System.OperationCanceledException])
        } finally { $script:OpCancellation = $null }
        Test-Path $dest | Should -BeFalse
        (Get-Item "$dest.part").Length | Should -BeGreaterThan 0
    }
}

Describe 'Invoke-OpBitsDownload (BITS simulé)' {
    BeforeAll {
        Mock Write-OpLog {}
        $script:dest = Join-Path $TestDrive 'bits\fichier.msu'
        $script:url = 'https://catalog.sf.dl.delivery.mp.microsoft.com/fichier.msu'
        function Get-FakeJob([string]$State, [long]$Bytes = 0, [string]$Flags = 'RedirectPolicyDisallow', [string]$Url = $script:url) {
            [pscustomobject]@{
                JobId = [guid]'11111111-1111-1111-1111-111111111111'; DisplayName = 'OffPatch fichier.msu'; JobState = $State
                BytesTransferred = $Bytes; SecurityFlags = $Flags; ErrorDescription = 'HTTP 404 introuvable'; ErrorContext = 'RemoteFile'
                FileList = @([pscustomobject]@{ RemoteName = $Url; LocalName = $script:dest })
            }
        }
        # Suite d'états renvoyés par Get-BitsTransfer -JobId, un par appel ; le dernier se répète.
        function Use-JobSequence([object[]]$Jobs) { $script:states = $Jobs; $script:stateIndex = 0 }
        function Get-NextJob {
            $job = $script:states[[Math]::Min($script:stateIndex, $script:states.Count - 1)]
            $script:stateIndex++
            $job
        }
        Mock Start-BitsTransfer { Get-FakeJob 'Suspended' }
        Mock Set-BitsTransfer -RemoveParameterType BitsJob {}
        Mock Resume-BitsTransfer -RemoveParameterType BitsJob {}
        Mock Complete-BitsTransfer -RemoveParameterType BitsJob {}
        Mock Remove-BitsTransfer -RemoveParameterType BitsJob {}
        Mock Get-BitsTransfer -ParameterFilter { -not $JobId } { @() }
        Mock Get-BitsTransfer -ParameterFilter { $JobId } { Get-NextJob }
        Mock Start-Sleep {}
    }

    It 'crée le travail suspendu, pose le refus des redirections, puis termine le transfert' {
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'Transferring' 10), (Get-FakeJob 'Transferred' 20))
        $r = Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10
        $r.Engine | Should -Be 'BITS'
        $r.Resumed | Should -BeFalse
        Should -Invoke Start-BitsTransfer -Times 1 -Exactly -ParameterFilter { $Suspended -and $Asynchronous -and $DisplayName -eq 'OffPatch fichier.msu' }
        Should -Invoke Set-BitsTransfer -Times 1 -Exactly -ParameterFilter { "$SecurityFlags" -eq 'RedirectPolicyDisallow' }
        Should -Invoke Resume-BitsTransfer -Times 1 -Exactly
        Should -Invoke Complete-BitsTransfer -Times 1 -Exactly
    }

    It 'déclare BITS indisponible si le refus des redirections n''est pas appliqué' {
        Use-JobSequence @((Get-FakeJob 'Suspended' 0 'RedirectPolicyAllowSilent'))
        { Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10 } | Should -Throw -ExceptionType ([System.NotSupportedException])
        Should -Invoke Remove-BitsTransfer -Times 1 -Exactly
        Should -Invoke Resume-BitsTransfer -Times 0 -Exactly
    }

    It 'reprend le travail laissé par un lancement interrompu au lieu d''en créer un autre' {
        Mock Get-BitsTransfer -ParameterFilter { -not $JobId } { Get-FakeJob 'TransientError' 500 }
        Use-JobSequence @((Get-FakeJob 'Transferred' 1000))
        $r = Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10
        $r.Resumed | Should -BeTrue
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
        Should -Invoke Resume-BitsTransfer -Times 1 -Exactly
        Should -Invoke Complete-BitsTransfer -Times 1 -Exactly
    }

    It 'supprime un ancien travail du même nom vers une autre URL et en crée un nouveau' {
        Mock Get-BitsTransfer -ParameterFilter { -not $JobId } { Get-FakeJob 'Error' 500 'RedirectPolicyDisallow' 'https://catalog.sf.dl.delivery.mp.microsoft.com/ancien.msu' }
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'Transferred' 20))
        (Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10).Resumed | Should -BeFalse
        Should -Invoke Remove-BitsTransfer -Times 1 -Exactly
        Should -Invoke Start-BitsTransfer -Times 1 -Exactly
    }

    It 'supprime le travail et donne la description de BITS sur une erreur définitive' {
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'Error'))
        { Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10 } | Should -Throw -ExpectedMessage '*HTTP 404 introuvable*RemoteFile*'
        Should -Invoke Remove-BitsTransfer -Times 1 -Exactly
    }

    It 'déclare BITS indisponible quand le travail reste en file d''attente sans transfert' {
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'Queued'))
        $script:clock = [datetime]'2026-10-11 10:00:00'
        Mock Get-Date { $script:clock = $script:clock.AddSeconds(5); $script:clock }
        { Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -QueuedSeconds 30 -PollMilliseconds 10 } | Should -Throw -ExceptionType ([System.NotSupportedException])
        Should -Invoke Remove-BitsTransfer -Times 1 -Exactly
    }

    It 'garde le travail pour une reprise ultérieure quand le transfert ne progresse plus' {
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'TransientError' 700))
        $script:clock = [datetime]'2026-10-11 10:00:00'
        Mock Get-Date { $script:clock = $script:clock.AddSeconds(5); $script:clock }
        { Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -StallSeconds 30 -PollMilliseconds 10 } | Should -Throw -ExpectedMessage '*conservé, reprise au prochain lancement*'
        Should -Invoke Remove-BitsTransfer -Times 0 -Exactly
    }

    It 'suspend le travail, sans le supprimer, à la demande d''annulation' {
        Mock Suspend-BitsTransfer -RemoveParameterType BitsJob {}
        Use-JobSequence @((Get-FakeJob 'Suspended'), (Get-FakeJob 'Transferring' 10))
        $source = New-Object System.Threading.CancellationTokenSource
        $source.Cancel()
        $script:OpCancellation = $source.Token
        try {
            { Invoke-OpBitsDownload -Url $script:url -Destination $script:dest -PollMilliseconds 10 } | Should -Throw -ExceptionType ([System.OperationCanceledException])
        } finally { $script:OpCancellation = $null }
        Should -Invoke Suspend-BitsTransfer -Times 1 -Exactly
        Should -Invoke Remove-BitsTransfer -Times 0 -Exactly
        Should -Invoke Complete-BitsTransfer -Times 0 -Exactly
    }
}

Describe 'Save-OpDownload' {
    BeforeAll {
        Mock Write-OpLog {}
        $script:url = 'https://catalog.sf.dl.delivery.mp.microsoft.com/fichier.msu'
        function Write-FakeFile([string]$Path, [int]$Size) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
            [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] $Size))
        }
    }

    It 'refuse un lien non https' {
        { Save-OpDownload -Url 'http://catalog.sf.dl.delivery.mp.microsoft.com/a.msu' -Destination (Join-Path $TestDrive 'a.msu') } | Should -Throw -ExpectedMessage '*non https*'
    }

    It 'passe à HttpClient quand BITS est indisponible et crée le dossier temporaire' {
        $dest = Join-Path $TestDrive 'depot\.tmp\a.msu'
        Mock Invoke-OpBitsDownload { throw (New-Object System.NotSupportedException('BITS indisponible : essai.')) }
        Mock Invoke-OpHttpDownload { Write-FakeFile $Destination 100; [pscustomobject]@{ Path = $Destination; Engine = 'HttpClient'; Resumed = $false; SizeBytes = 100 } }
        $r = Save-OpDownload -Url $script:url -Destination $dest -ExpectedSize 100
        $r.Engine | Should -Be 'HttpClient'
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -like '*Repli sur HttpClient*' }
    }

    It 'ne se replie pas sur une autre erreur de BITS' {
        Mock Invoke-OpBitsDownload { throw 'Téléchargement BITS en échec : HTTP 404' }
        Mock Invoke-OpHttpDownload { throw 'ne doit pas être appelé' }
        { Save-OpDownload -Url $script:url -Destination (Join-Path $TestDrive 'b.msu') } | Should -Throw -ExpectedMessage '*HTTP 404*'
    }

    It 'ne se replie pas quand BITS est imposé' {
        Mock Invoke-OpBitsDownload { throw (New-Object System.NotSupportedException('BITS indisponible : essai.')) }
        Mock Invoke-OpHttpDownload { throw 'ne doit pas être appelé' }
        { Save-OpDownload -Url $script:url -Destination (Join-Path $TestDrive 'c.msu') -Engine Bits } | Should -Throw -ExceptionType ([System.NotSupportedException])
    }

    It 'garde un fichier déjà complet dans le dossier temporaire sans le retélécharger' {
        $dest = Join-Path $TestDrive 'd.msu'
        Write-FakeFile $dest 50
        Mock Invoke-OpBitsDownload { throw 'ne doit pas être appelé' }
        (Save-OpDownload -Url $script:url -Destination $dest -ExpectedSize 50).Engine | Should -Be 'Existing'
    }

    It 'supprime un fichier dont la taille diffère de la taille attendue' {
        $dest = Join-Path $TestDrive 'e.msu'
        Mock Invoke-OpBitsDownload { Write-FakeFile $Destination 99; [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $false; SizeBytes = 99 } }
        { Save-OpDownload -Url $script:url -Destination $dest -ExpectedSize 100 } | Should -Throw -ExpectedMessage '*99 octet(s) reçus, 100 attendus*'
        Test-Path $dest | Should -BeFalse
    }

    It 'ne télécharge rien avec -WhatIf' {
        $dest = Join-Path $TestDrive 'whatif\f.msu'
        Mock Invoke-OpBitsDownload { throw 'ne doit pas être appelé' }
        Save-OpDownload -Url $script:url -Destination $dest -WhatIf
        Test-Path (Split-Path -Parent $dest) | Should -BeFalse
    }
}
