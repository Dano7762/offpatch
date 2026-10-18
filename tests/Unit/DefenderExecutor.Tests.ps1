# Exécuteur Defender (cahier des charges 8.4, R-06) : plateforme puis définitions, jugement par la version relevée,
# jamais par le code retour. Get-MpComputerStatus, Invoke-OpProcess et Start-Sleep simulés : rien n'est lancé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($name in 'ConvertTo-OpMaskedText', 'Write-OpLog', 'Invoke-OpProcess', 'Test-OpItemFileHash', 'Get-OpDefenderRunningMode', 'Install-OpDefenderUpdate') {
        . (Join-Path $root "app\module\OffPatch\Private\$name.ps1")
    }

    function Get-DefenderScene([string]$Category, [string]$Version, [switch]$Corrupt) {
        # Un fichier au dépôt simulé, rangé sous files/<sha256>/ comme le vrai.
        $depot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $content = Join-Path $depot 'content.exe'
        New-Item -ItemType Directory -Force -Path $depot | Out-Null
        Set-Content -Path $content -Value 'exécutable simulé' -Encoding UTF8
        $sha = (Get-FileHash -LiteralPath $content -Algorithm SHA256).Hash.ToLowerInvariant()
        $name = 'mpam-fe.exe'
        if ($Category -eq 'defender-platform') { $name = 'updateplatform.amd64fre.exe' }
        New-Item -ItemType Directory -Force -Path (Join-Path $depot "files\$sha") | Out-Null
        Move-Item -Path $content -Destination (Join-Path $depot "files\$sha\$name")
        if ($Corrupt) { Add-Content -Path (Join-Path $depot "files\$sha\$name") -Value 'altéré' }
        [pscustomobject]@{
            Depot = $depot
            Item  = [pscustomobject]@{ id = "win11-x64-$Category-$Version"; category = $Category; version = $Version; files = @([pscustomobject]@{ path = "files/$sha/$name"; sha256 = $sha; size = 1 }) }
        }
    }

    # Relevés successifs de Get-MpComputerStatus ; le dernier se répète.
    function Use-DefenderReading([object[]]$Readings) {
        $script:readings = $Readings
        $script:reading = 0
        Mock Get-MpComputerStatus {
            $r = $script:readings[[math]::Min($script:reading, $script:readings.Count - 1)]
            $script:reading++
            if ($r -is [string]) { throw $r }
            [pscustomobject]$r
        }
    }
    function Get-Ok([int]$Code = 0) { [pscustomobject]@{ ExitCode = $Code; TimedOut = $false; StdOut = ''; StdErr = ''; Seconds = 1 } }
}

Describe 'Test-OpItemFileHash' {
    It 'ne signale rien pour un fichier conforme' {
        $s = Get-DefenderScene 'defender' '1.459.553.0'
        @(Test-OpItemFileHash -Depot $s.Depot -File $s.Item.files).Count | Should -Be 0
    }

    It 'signale un fichier altéré et un fichier absent' {
        $s = Get-DefenderScene 'defender' '1.459.553.0' -Corrupt
        $missing = [pscustomobject]@{ path = 'files/absent/mpam-fe.exe'; sha256 = ('0' * 64); size = 1 }
        $r = @(Test-OpItemFileHash -Depot $s.Depot -File @($s.Item.files[0], $missing))
        $r.Count | Should -Be 2
        $r[0] | Should -Match 'SHA-256'
        $r[1] | Should -Match 'absent'
    }
}

Describe 'Install-OpDefenderUpdate' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-OpLog {}
    }

    Context 'plateforme Defender' {
        It 'part d''une plateforme ancienne sans AMRunningMode sans attendre, et réussit quand la nouvelle le porte' {
            $s = Get-DefenderScene 'defender-platform' '4.18.26080.4'
            Use-DefenderReading @(
                @{ AMServiceEnabled = $true; AntivirusEnabled = $true; AMProductVersion = '4.18.1909.6' }
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.26080.4' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'UpToDate'
            $r.Before | Should -Be '4.18.1909.6'
            Should -Invoke Start-Sleep -Times 0 -Exactly
            Should -Invoke Write-OpLog -Times 0 -Exactly -ParameterFilter { $Level -eq 'WARN' }
        }

        It 'lance l''exécutable sans argument et réussit quand AMProductVersion atteint la version du dépôt' {
            $s = Get-DefenderScene 'defender-platform' '4.18.26080.4'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.25080.5' }
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.26080.4' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'UpToDate'
            $r.Before | Should -Be '4.18.25080.5'
            $r.Installed | Should -Be '4.18.26080.4'
            Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { @($ArgumentList).Count -eq 0 -and $FilePath -like '*updateplatform.amd64fre.exe' }
        }

        It 'attend le retour de Defender en mode Normal, puis juge sur la version' {
            $s = Get-DefenderScene 'defender-platform' '4.18.26080.4'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.25080.5' }
                'service arrêté'
                @{ AMRunningMode = 'Not running'; AMProductVersion = '4.18.26080.4' }
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.26080.4' })
            Mock Invoke-OpProcess { Get-Ok }
            (Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot).State | Should -Be 'UpToDate'
            Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 5 }
        }

        It 'avertit quand Defender ne revient pas dans le délai, sans bloquer au-delà' {
            $s = Get-DefenderScene 'defender-platform' '4.18.26080.4'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.25080.5' }
                @{ AMRunningMode = 'Not running'; AMProductVersion = '4.18.26080.4' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot -WaitSeconds 120
            $r.State | Should -Be 'UpToDate'
            Should -Invoke Start-Sleep -Times 24 -Exactly
            Should -Invoke Write-OpLog -ParameterFilter { $Level -eq 'WARN' -and $Message -match "pas revenu en mode Normal" }
        }

        It 'est en erreur avec le code retour si la version ne change pas, sans seconde tentative' {
            $s = Get-DefenderScene 'defender-platform' '4.18.26080.4'
            Use-DefenderReading @(@{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.25080.5' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match 'code retour 0'
            Should -Invoke Invoke-OpProcess -Times 1 -Exactly
        }
    }

    Context 'définitions Defender' {
        It 'lance mpam-fe.exe -q et réussit quand AntivirusSignatureVersion atteint la version du dépôt' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.553.0' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'UpToDate'
            $r.Installed | Should -Be '1.459.553.0'
            Should -Invoke Invoke-OpProcess -Times 1 -Exactly -ParameterFilter { $ArgumentList -join ' ' -eq '-q' -and $FilePath -like '*mpam-fe.exe' }
        }

        It 'retente une fois après 30 s quand le code 0 n''a rien appliqué' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.553.0' })
            Mock Invoke-OpProcess { Get-Ok }
            (Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot).State | Should -Be 'UpToDate'
            Should -Invoke Invoke-OpProcess -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
        }

        It 'est en erreur avec le code retour après deux tentatives sans effet' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(@{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' })
            Mock Invoke-OpProcess { Get-Ok -Code -2147023436 }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match '-2147023436'
            $r.ExitCode | Should -Be -2147023436
            Should -Invoke Invoke-OpProcess -Times 2 -Exactly
        }

        It 'attend que Defender soit en service avant de lancer mpam-fe.exe' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(
                'service arrêté'
                'service arrêté'
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.553.0' })
            Mock Invoke-OpProcess { if ($script:reading -lt 3) { throw 'lancé trop tôt' }; Get-Ok }
            (Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot).State | Should -Be 'UpToDate'
        }

        It 'accepte un Defender passif' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(
                @{ AMRunningMode = 'Passive Mode'; AntivirusSignatureVersion = '1.459.384.0' }
                @{ AMRunningMode = 'Passive Mode'; AntivirusSignatureVersion = '1.459.553.0' })
            Mock Invoke-OpProcess { Get-Ok }
            (Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot).State | Should -Be 'UpToDate'
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }
    }

    Context 'garde-fous' {
        It 'ne lance rien si le fichier ne correspond plus au manifeste' {
            $s = Get-DefenderScene 'defender' '1.459.553.0' -Corrupt
            Use-DefenderReading @(@{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' })
            Mock Invoke-OpProcess { Get-Ok }
            $r = Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot
            $r.State | Should -Be 'Error'
            $r.Reason | Should -Match 'SHA-256'
            Should -Invoke Invoke-OpProcess -Times 0 -Exactly
        }

        It 'respecte -WhatIf' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            Use-DefenderReading @(@{ AMRunningMode = 'Normal'; AntivirusSignatureVersion = '1.459.384.0' })
            Mock Invoke-OpProcess { Get-Ok }
            Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot -WhatIf | Should -BeNullOrEmpty
            Should -Invoke Invoke-OpProcess -Times 0 -Exactly
        }

        It 'refuse une autre catégorie' {
            $s = Get-DefenderScene 'defender' '1.459.553.0'
            $s.Item.category = 'windows-lcu'
            { Install-OpDefenderUpdate -Item $s.Item -Depot $s.Depot } | Should -Throw '*non prise en charge*'
        }
    }
}
