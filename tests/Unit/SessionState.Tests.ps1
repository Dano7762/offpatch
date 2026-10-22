# État de session state.json (cahier des charges 8.6, 11) : contenu initial, identité du support, écriture atomique,
# lecture stricte, archivage en fin de session. Tout dans TestDrive ; WMI simulé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Get-OpSupportIdentity', 'Get-OpInitialSessionState', 'Read-OpSessionState', 'Save-OpSessionState', 'Complete-OpSessionState', 'Get-OpPath') {
        . (Join-Path $repo "app\module\OffPatch\Private\$name.ps1")
    }
    function Get-Info { [pscustomobject]@{ ComputerName = 'PC'; Office = [pscustomobject]@{ Version = [version]'16.0.1.2' } } }
}

Describe 'Get-OpSupportIdentity' {
    It 'donne le numéro de série du volume et la racine sans lettre : <Root>' -TestCases @(
        @{ Root = 'E:\'; Drive = 'E:'; Relative = '.' }
        @{ Root = 'E:\OffPatch'; Drive = 'E:'; Relative = 'OffPatch' }
        @{ Root = 'F:\Outils\OffPatch\'; Drive = 'F:'; Relative = 'Outils\OffPatch' }
    ) {
        param($Root, $Drive, $Relative)
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = $Drive; VolumeSerialNumber = '1A2B3C4D' } }
        $r = Get-OpSupportIdentity -Root $Root
        $r.Drive | Should -Be $Drive
        $r.RelativeRoot | Should -Be $Relative
        $r.VolumeSerial | Should -Be '1A2B3C4D'
        Should -Invoke Get-CimInstance -ParameterFilter { $Filter -eq "DeviceID='$Drive'" }
    }

    It 'renvoie un numéro de série vide, avec un avertissement, si WMI échoue' {
        Mock Get-CimInstance { throw 'WMI indisponible' }
        Mock Write-OpLog {}
        (Get-OpSupportIdentity -Root 'E:\OffPatch').VolumeSerial | Should -BeNullOrEmpty
        Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' }
    }
}

Describe 'state.json' {
    BeforeEach {
        Mock Write-OpLog {}
        Mock Get-CimInstance { [pscustomobject]@{ VolumeSerialNumber = '1A2B3C4D' } }
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:path = Join-Path $script:dir 'state.json'
        $script:logs = Join-Path $script:dir 'logs'
    }

    It 'construit l''état initial (8.6) avec des valeurs sérialisables' {
        $restore = [pscustomobject]@{ Status = 'Created'; CreationTime = Get-Date }
        $s = Get-OpInitialSessionState -Root 'E:\OffPatch' -SystemInfo (Get-Info) -RestorePoint $restore
        $s.schemaVersion | Should -Be 1
        $s.sessionId | Should -Match '^[0-9a-f]{8}-'
        $s.mode | Should -Be 'Manual'
        $s.rebootCount | Should -Be 0
        $s.support.volumeSerial | Should -Be '1A2B3C4D'
        $s.support.relativeRoot | Should -Be 'OffPatch'
        $s.before.Office.Version | Should -BeOfType [string]
        $s.restorePoint.CreationTime | Should -BeOfType [string]
        @($s.steps).Count | Should -Be 0
    }

    It 'écrit, réécrit et relit l''état sans laisser de fichier temporaire' {
        $s = Get-OpInitialSessionState -Root 'E:\OffPatch' -SystemInfo (Get-Info)
        Save-OpSessionState -State $s -Path $script:path
        $s.rebootCount = 2
        Save-OpSessionState -State $s -Path $script:path
        $r = Read-OpSessionState -Path $script:path
        $r.sessionId | Should -Be $s.sessionId
        $r.rebootCount | Should -Be 2
        Test-Path ($script:path + '.tmp') | Should -BeFalse
    }

    It 'garde l''état précédent intact quand un fichier temporaire est resté d''une écriture interrompue' {
        $s = Get-OpInitialSessionState -Root 'E:\OffPatch' -SystemInfo (Get-Info)
        Save-OpSessionState -State $s -Path $script:path
        Set-Content -LiteralPath ($script:path + '.tmp') -Value '{ "coupé' -Encoding UTF8
        (Read-OpSessionState -Path $script:path).sessionId | Should -Be $s.sessionId
        Save-OpSessionState -State $s -Path $script:path
        (Read-OpSessionState -Path $script:path).sessionId | Should -Be $s.sessionId
    }

    It 'renvoie $null sans session, refuse un état illisible ou d''un autre schéma' {
        Read-OpSessionState -Path $script:path | Should -BeNullOrEmpty
        New-Item -ItemType Directory -Force -Path $script:dir | Out-Null
        Set-Content -LiteralPath $script:path -Value '{ pas du json' -Encoding UTF8
        { Read-OpSessionState -Path $script:path } | Should -Throw '*illisible*'
        Set-Content -LiteralPath $script:path -Value '{ "schemaVersion": 2, "sessionId": "x" }' -Encoding UTF8
        { Read-OpSessionState -Path $script:path } | Should -Throw '*non reconnu*'
    }

    It 'archive l''état dans les journaux en fin de session' {
        $s = Get-OpInitialSessionState -Root 'E:\OffPatch' -SystemInfo (Get-Info)
        Save-OpSessionState -State $s -Path $script:path
        $archive = Complete-OpSessionState -Path $script:path -LogDirectory $script:logs
        Split-Path -Leaf $archive | Should -Match ('^state_\d{4}-\d{2}-\d{2}_\d{6}_' + [regex]::Escape($s.sessionId) + '\.json$')
        Test-Path $script:path | Should -BeFalse
        (Get-Content -LiteralPath $archive -Raw -Encoding UTF8 | ConvertFrom-Json).sessionId | Should -Be $s.sessionId
        Complete-OpSessionState -Path $script:path -LogDirectory $script:logs | Should -BeNullOrEmpty
    }

    It 'respecte -WhatIf à l''écriture et à l''archivage' {
        $s = Get-OpInitialSessionState -Root 'E:\OffPatch' -SystemInfo (Get-Info)
        Save-OpSessionState -State $s -Path $script:path -WhatIf
        Test-Path $script:path | Should -BeFalse
        Save-OpSessionState -State $s -Path $script:path
        Complete-OpSessionState -Path $script:path -LogDirectory $script:logs -WhatIf | Should -BeNullOrEmpty
        Test-Path $script:path | Should -BeTrue
    }
}

Describe 'Get-OpSessionStatus' {
    BeforeAll { . (Join-Path $repo 'app\module\OffPatch\Public\Get-OpSessionStatus.ps1') }

    It 'aucune session : rien' {
        Get-OpSessionStatus -Path (Join-Path $TestDrive 'absent.json') | Should -BeNullOrEmpty
    }

    It 'session automatique : mode, redémarrages, étapes' {
        $path = Join-Path $TestDrive 'auto.json'
        Set-Content -LiteralPath $path -Encoding UTF8 -Value '{"schemaVersion":1,"sessionId":"s1","mode":"Auto","startTime":"2026-10-22T08:00:00","rebootCount":2,"steps":[{"Id":"a"},{"Id":"b"}]}'
        $s = Get-OpSessionStatus -Path $path
        "$($s.SessionId) $($s.Mode) $($s.RebootCount) $($s.StepCount)" | Should -Be 's1 Auto 2 2'
        $s.Error | Should -BeNullOrEmpty
    }

    It 'état illisible : motif dans Error, pas d''exception' {
        $path = Join-Path $TestDrive 'casse.json'
        Set-Content -LiteralPath $path -Encoding UTF8 -Value '{"schemaVersion":2}'
        $s = Get-OpSessionStatus -Path $path
        $s.Mode | Should -BeNullOrEmpty
        $s.Error | Should -Match 'non reconnu'
    }
}
