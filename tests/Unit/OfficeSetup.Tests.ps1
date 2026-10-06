# Étape Office (cahier des charges 8.5) : copie des journaux de l'ODT et suppression du XML sur tous les chemins de
# sortie (réussite, erreur, délai dépassé, exception). setup.exe simulé ; journaux simulés dans un TEMP de test.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Invoke-OpProcess', 'Invoke-OpOfficeSetup') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }

    function Get-OdtScene {
        # Un TEMP simulé avec un journal de l'ODT de l'étape, un ancien journal, un XML de mise à jour.
        $scene = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $temp = Join-Path $scene 'temp'
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        Set-Content -Path (Join-Path $temp "$env:COMPUTERNAME-20261006-0744.log") -Value 'journal de l''étape' -Encoding Unicode
        $old = Join-Path $temp "$env:COMPUTERNAME-20260901-1000.log"
        Set-Content -Path $old -Value 'ancien journal' -Encoding Unicode
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)
        $xml = Join-Path $scene 'update.xml'
        Set-Content -Path $xml -Value '<Configuration><Add SourcePath="E:\depot\office\current" Channel="Current" AllowCdnFallback="FALSE" /></Configuration>' -Encoding UTF8
        [pscustomobject]@{ Temp = $temp; Session = (Join-Path $scene 'session\odt'); Xml = $xml; Old = $old; Setup = (Join-Path $scene 'odt\setup.exe') }
    }
}

Describe 'Invoke-OpOfficeSetup' {
    It 'copie les journaux de l''étape et supprime le XML quand <Cas>' -TestCases @(
        @{ Cas = 'le délai est dépassé'; Result = @{ ExitCode = $null; TimedOut = $true } }
        @{ Cas = 'l''ODT réussit'; Result = @{ ExitCode = 0; TimedOut = $false } }
        @{ Cas = 'l''ODT échoue (17002)'; Result = @{ ExitCode = 17002; TimedOut = $false } }
    ) {
        param($Cas, $Result)
        $s = Get-OdtScene
        $script:fake = [pscustomobject]@{ ExitCode = $Result.ExitCode; TimedOut = $Result.TimedOut; StdOut = ''; StdErr = ''; Seconds = 1 }
        Mock Invoke-OpProcess { $script:fake }
        $r = Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session
        $r.TimedOut | Should -Be $Result.TimedOut -Because $Cas
        Test-Path (Join-Path $s.Session "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
        Test-Path (Join-Path $s.Session (Split-Path -Leaf $s.Old)) | Should -BeFalse
        Test-Path $s.Xml | Should -BeFalse
        @($r.OdtLogs).Count | Should -Be 1
    }

    It 'copie aussi quand l''étape lève une exception, et laisse passer l''exception d''origine' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { throw 'setup.exe introuvable' }
        { Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session } |
            Should -Throw -ExpectedMessage '*setup.exe introuvable*'
        Test-Path (Join-Path $s.Session "$env:COMPUTERNAME-20261006-0744.log") | Should -BeTrue
        Test-Path $s.Xml | Should -BeFalse
    }

    It 'passe le délai en secondes à Invoke-OpProcess' {
        $s = Get-OdtScene
        Mock Invoke-OpProcess { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = ''; Seconds = 1 } }
        Invoke-OpOfficeSetup -SetupPath $s.Setup -ConfigPath $s.Xml -TimeoutMinutes 30 -LogSearchDirectory $s.Temp -SessionLogDirectory $s.Session | Out-Null
        Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 1800 -and $ArgumentList[0] -eq '/configure' }
    }
}

Describe 'ConvertTo-OpMaskedText' {
    It 'masque une chaîne de forme de clé, sans tenir compte de la casse' {
        ConvertTo-OpMaskedText -Text 'clé abcde-12345-FGHIJ-67890-KLMNO fin' | Should -Be 'clé XXXXX-XXXXX-XXXXX-XXXXX-XXXXX fin'
    }

    It 'laisse intact un texte sans forme de clé' {
        ConvertTo-OpMaskedText -Text 'Version 16.0.17932.21000, code 0' | Should -Be 'Version 16.0.17932.21000, code 0'
    }
}
