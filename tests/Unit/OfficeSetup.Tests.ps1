# Étape Office (cahier des charges 8.5) : masquage des journaux de l'ODT et suppression du XML sur tous les chemins de
# sortie (réussite, délai dépassé, exception). setup.exe simulé ; journal de fixture UTF-16 avec une fausse clé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Protect-OpLogFile', 'Protect-OpOdtLog', 'Invoke-OpProcess', 'Invoke-OpOfficeSetup') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }
    $fakeKey = 'BCDFG-HJKMP-QRTVW-XY234-6789B'
    $fixture = Join-Path $root 'tests\Fixtures\odt\odt-journal-principal-utf16.log'

    function Get-OdtScene {
        # Un TEMP simulé avec un journal de l'ODT de l'étape, un ancien journal, un XML contenant la clé.
        $scene = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $temp = Join-Path $scene 'temp'
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $current = Join-Path $temp "$env:COMPUTERNAME-20261006-0744.log"
        Copy-Item -Path $fixture -Destination $current
        (Get-Item $current).LastWriteTime = Get-Date
        $old = Join-Path $temp "$env:COMPUTERNAME-20260901-1000.log"
        Copy-Item -Path $fixture -Destination $old
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)
        $xml = Join-Path $scene 'install.xml'
        Set-Content -Path $xml -Value "<Configuration><Add><Product ID=""ProPlus2024Volume"" PIDKEY=""$fakeKey"" /></Add></Configuration>" -Encoding UTF8
        [pscustomobject]@{ Temp = $temp; Session = (Join-Path $scene 'session\odt'); Xml = $xml; Old = $old; Setup = (Join-Path $scene 'odt\setup.exe') }
    }
    function Test-Masked([string]$Path) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        ('{0:X2}{1:X2}' -f $bytes[0], $bytes[1]) -eq 'FFFE' -and $text -notmatch '(?i)BCDFG|6789B'
    }
}

Describe 'Invoke-OpOfficeSetup' {
    It 'masque les journaux de l''ODT et supprime le XML quand le délai est dépassé' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = ''; StdErr = ''; Seconds = 1800 } }
        $r = Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -ProductKey $fakeKey -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session
        $r.TimedOut | Should -BeTrue
        Test-Masked (Join-Path $s.Temp "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
        Test-Masked (Join-Path $s.Session "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
        Test-Path $s.Xml | Should -BeFalse
        @($r.OdtLogs).Count | Should -Be 1
    }

    It 'masque aussi quand l''étape lève une exception, et laisse passer l''exception d''origine' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { throw 'setup.exe introuvable' }
        { Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -ProductKey $fakeKey -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session } |
            Should -Throw -ExpectedMessage '*setup.exe introuvable*'
        Test-Masked (Join-Path $s.Temp "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
        Test-Path $s.Xml | Should -BeFalse
    }

    It 'masque après une réussite et une erreur de l''ODT' -TestCases @(@{ Code = 0 }, @{ Code = 17002 }) {
        param($Code)
        $s = Get-OdtScene
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = $Code; TimedOut = $false; StdOut = ''; StdErr = ''; Seconds = 200 } }
        $r = Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -ProductKey $fakeKey -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session
        $r.ExitCode | Should -Be $Code
        Test-Masked (Join-Path $s.Session "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
    }

    It 'signale au rapport un journal resté non masqué dans TEMP, avec son chemin complet, sans le copier' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; Seconds = 1 } }
        Mock Protect-OpLogFile { throw 'fichier verrouillé' }
        $r = Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -ProductKey $fakeKey -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session
        $log = Join-Path $s.Temp "$env:COMPUTERNAME-20261006-0744.log"
        @($r.OdtLogs)[0].ReportNote | Should -Be "journal ODT non masqué resté dans TEMP : $log"
        @($r.OdtLogs)[0].Copied | Should -BeFalse
        Test-Path (Join-Path $s.Session "$env:COMPUTERNAME-20261006-0744.log") | Should -BeFalse
        Test-Path $s.Xml | Should -BeFalse
    }

    It 'ne touche pas aux journaux antérieurs à l''étape et passe le délai à Invoke-OpProcess' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; Seconds = 1 } }
        Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -ProductKey $fakeKey -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session | Out-Null
        [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($s.Old)) | Should -Match 'BCDFG'
        Test-Path (Join-Path $s.Session (Split-Path -Leaf $s.Old)) | Should -BeFalse
        Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 1800 }
    }
}
