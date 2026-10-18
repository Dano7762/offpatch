# Tâche planifiée OffPatch-Reprise (cahier des charges 8.6, R-18) : copie de resume.ps1, déclencheur à l'ouverture de
# session de l'utilisateur de la console, privilèges les plus élevés, batterie autorisée ; suppression. Module
# ScheduledTasks simulé : aucune tâche réelle n'est créée.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpPath', 'Register-OpResumeTask', 'Unregister-OpResumeTask') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
}

Describe 'Register-OpResumeTask' {
    BeforeEach {
        Mock Write-OpLog {}
        $script:tool = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path (Join-Path $script:tool 'app') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:tool 'app\resume.ps1') -Value '# amorce' -Encoding UTF8
        $script:target = Join-Path $script:tool 'programdata\resume.ps1'
        Mock Get-OpPath { $script:target } -ParameterFilter { $Name -eq 'ClientResume' }
        Mock Get-CimInstance { [pscustomobject]@{ UserName = 'PC\utilisateur' } }
        # New-ScheduledTask* ne font que construire des objets CIM en mémoire : réels ici ; seul l'enregistrement est simulé.
        Mock Register-ScheduledTask {
            $script:registered = [pscustomobject]@{ Name = $TaskName; Action = $Action; Trigger = $Trigger; Principal = $Principal; Settings = $Settings; Force = [bool]$Force }
        }
    }

    It 'copie resume.ps1 et crée la tâche à l''ouverture de session, privilèges les plus élevés, sur batterie aussi' {
        $r = Register-OpResumeTask -Root $script:tool
        $r.User | Should -Be 'PC\utilisateur'
        Test-Path -LiteralPath $script:target | Should -BeTrue
        $t = $script:registered
        $t.Name | Should -Be 'OffPatch-Reprise'
        $t.Force | Should -BeTrue
        @($t.Trigger)[0].CimClass.CimClassName | Should -Be 'MSFT_TaskLogonTrigger'
        @($t.Trigger)[0].UserId | Should -Be 'PC\utilisateur'
        $t.Principal.UserId | Should -Be 'PC\utilisateur'
        [string]$t.Principal.LogonType | Should -Be 'Interactive'
        [string]$t.Principal.RunLevel | Should -Be 'Highest'
        $t.Settings.DisallowStartIfOnBatteries | Should -BeFalse
        $t.Settings.StopIfGoingOnBatteries | Should -BeFalse
        @($t.Action)[0].Execute | Should -Be (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        @($t.Action)[0].Arguments | Should -BeLike "*-File `"$script:target`""
    }

    It 'se rabat sur l''identité courante, avec un avertissement, si la console ne donne pas d''utilisateur' {
        Mock Get-CimInstance { [pscustomobject]@{ UserName = $null } }
        $r = Register-OpResumeTask -Root $script:tool
        $r.User | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' }
    }

    It 'refuse sans resume.ps1 dans l''outil' {
        Remove-Item -LiteralPath (Join-Path $script:tool 'app\resume.ps1')
        { Register-OpResumeTask -Root $script:tool } | Should -Throw '*resume.ps1 absent*'
        Should -Invoke Register-ScheduledTask -Times 0 -Exactly
    }

    It 'respecte -WhatIf' {
        Register-OpResumeTask -Root $script:tool -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Register-ScheduledTask -Times 0 -Exactly
        Test-Path -LiteralPath $script:target | Should -BeFalse
    }
}

Describe 'Unregister-OpResumeTask' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Unregister-ScheduledTask {}
    }

    It 'supprime la tâche existante' {
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'OffPatch-Reprise' } }
        Unregister-OpResumeTask | Should -BeTrue
        Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'OffPatch-Reprise' }
    }

    It 'ne fait rien sans tâche, ni avec -WhatIf' {
        Mock Get-ScheduledTask { $null }
        Unregister-OpResumeTask | Should -BeFalse
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'OffPatch-Reprise' } }
        Unregister-OpResumeTask -WhatIf | Should -BeFalse
        Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
    }
}
