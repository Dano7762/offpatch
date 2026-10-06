# Lancement des processus (R-14) : codes de sortie, délai dépassé, sorties capturées. Processus réels inoffensifs
# (cmd.exe /c exit, echo, ping vers la boucle locale) ; aucune modification du système.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'app\module\OffPatch\Private\Invoke-OpProcess.ps1')
    $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
}

Describe 'Invoke-OpProcess' {
    It 'renvoie le code de sortie <Code>' -TestCases @(@{ Code = 0 }, @{ Code = 3010 }, @{ Code = 1618 }) {
        param($Code)
        $r = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', "exit $Code"
        $r.ExitCode | Should -Be $Code
        $r.TimedOut | Should -BeFalse
    }

    It 'arrête le processus quand le délai est dépassé' {
        $r = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'ping -n 30 127.0.0.1 >nul' -TimeoutSeconds 2
        $r.TimedOut | Should -BeTrue
        $r.ExitCode | Should -BeNullOrEmpty
        $r.Seconds | Should -BeLessThan 20
    }

    It 'capture la sortie standard et la sortie d''erreur' {
        $r = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'echo bonjour & echo erreur 1>&2'
        $r.StdOut.Trim() | Should -Be 'bonjour'
        $r.StdErr.Trim() | Should -Be 'erreur'
    }

    It 'lit une sortie volumineuse sans se bloquer' {
        $r = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'for /L %i in (1,1,20000) do @echo ligne %i' -TimeoutSeconds 60
        $r.TimedOut | Should -BeFalse
        ($r.StdOut -split "`r?`n" | Where-Object { $_ }).Count | Should -Be 20000
    }

    It 'met entre guillemets un argument qui contient un espace' {
        $r = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'echo', 'deux mots' -WhatIf
        $r | Should -BeNullOrEmpty
        $quoted = Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'echo', 'deux mots'
        $quoted.Arguments | Should -Be '/c echo "deux mots"'
    }

    It 'respecte -WhatIf : aucun processus lancé' {
        Invoke-OpProcess -FilePath $cmd -ArgumentList '/c', 'exit 5' -WhatIf | Should -BeNullOrEmpty
    }
}
