# Amorce de reprise app\resume.ps1 (cahier des charges 8.6) : support retrouvé par numéro de série et marqueur, même
# sous une autre lettre ; codes de sortie ; aucune relance réelle (-WhatIf). Les « lecteurs » sont des dossiers de
# TestDrive renvoyés par Win32_LogicalDisk simulé.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $resume = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'app\resume.ps1'

    # Un « lecteur » : dossier de TestDrive, avec ou sans offpatch.root au chemin relatif.
    function Initialize-TestVolume([string]$Name, [string]$Relative, [switch]$Marker) {
        $drive = Join-Path $TestDrive $Name
        $root = $drive
        if ($Relative -and $Relative -ne '.') { $root = Join-Path $drive $Relative }
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        if ($Marker) { Set-Content -LiteralPath (Join-Path $root 'offpatch.root') -Value '' }
        $drive
    }
    # Lecteurs renvoyés par Win32_LogicalDisk simulé : fichier JSON désigné par une variable d'environnement, le mock
    # tournant dans la portée de resume.ps1.
    function Use-TestDisk([object[]]$Disk) {
        $path = Join-Path $TestDrive ("disks-{0}.json" -f [guid]::NewGuid())
        ConvertTo-Json -InputObject @($Disk) | Set-Content -LiteralPath $path -Encoding UTF8
        $env:OP_RESUME_TEST_DISKS = $path
    }
    function Initialize-TestState([string]$Serial, [string]$Relative) {
        $path = Join-Path $TestDrive ("state-{0}.json" -f [guid]::NewGuid())
        $support = [ordered]@{ volumeSerial = $Serial; relativeRoot = $Relative }
        ([ordered]@{ schemaVersion = 1; sessionId = 's1'; support = $support } | ConvertTo-Json) | Set-Content -LiteralPath $path -Encoding UTF8
        $path
    }
}

Describe 'resume.ps1' {
    BeforeEach { Mock Get-CimInstance { (Get-Content -LiteralPath $env:OP_RESUME_TEST_DISKS -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ } } }
    AfterEach { Remove-Item -Path Env:OP_RESUME_TEST_DISKS -ErrorAction SilentlyContinue }

    It 'retrouve le support sous une autre lettre par son numéro de série et le marqueur' {
        $other = Initialize-TestVolume 'D' 'OffPatch' -Marker
        $support = Initialize-TestVolume 'F' 'OffPatch' -Marker
        Use-TestDisk @([pscustomobject]@{ DeviceID = $other; VolumeSerialNumber = '11111111' }, [pscustomobject]@{ DeviceID = $support; VolumeSerialNumber = '1A2B3C4D' })
        $found = & $resume -StatePath (Initialize-TestState '1A2B3C4D' 'OffPatch') -WhatIf
        $LASTEXITCODE | Should -Be 0
        $found | Should -Be (Join-Path $support 'OffPatch')
    }

    It 'trouve un support placé à la racine du volume (« . »)' {
        $support = Initialize-TestVolume 'G' '.' -Marker
        Use-TestDisk @([pscustomobject]@{ DeviceID = $support; VolumeSerialNumber = 'AAAA0001' })
        $found = & $resume -StatePath (Initialize-TestState 'AAAA0001' '.') -WhatIf
        $LASTEXITCODE | Should -Be 0
        $found.TrimEnd('\') | Should -Be $support
    }

    It 'sort en code 2 si le volume au bon numéro n''a pas le marqueur, ou si aucun volume ne correspond' {
        $empty = Initialize-TestVolume 'H' 'OffPatch'
        Use-TestDisk @([pscustomobject]@{ DeviceID = $empty; VolumeSerialNumber = '1A2B3C4D' })
        & $resume -StatePath (Initialize-TestState '1A2B3C4D' 'OffPatch') -WhatIf | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 2
        $marked = Initialize-TestVolume 'I' 'OffPatch' -Marker
        Use-TestDisk @([pscustomobject]@{ DeviceID = $marked; VolumeSerialNumber = '99999999' })
        & $resume -StatePath (Initialize-TestState '1A2B3C4D' 'OffPatch') -WhatIf | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 2
    }

    It 'se contente du marqueur quand l''état ne connaît pas le numéro de série' {
        $support = Initialize-TestVolume 'J' 'Outil' -Marker
        Use-TestDisk @([pscustomobject]@{ DeviceID = $support; VolumeSerialNumber = '12345678' })
        $found = & $resume -StatePath (Initialize-TestState $null 'Outil') -WhatIf
        $LASTEXITCODE | Should -Be 0
        $found | Should -Be (Join-Path $support 'Outil')
    }

    It 'sort en code 1 sans état de session ou sur un état illisible' {
        & $resume -StatePath (Join-Path $TestDrive 'absent.json') -WhatIf | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 1
        $bad = Join-Path $TestDrive 'illisible.json'
        Set-Content -LiteralPath $bad -Value '{ pas du json' -Encoding UTF8
        & $resume -StatePath $bad -WhatIf | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 1
    }

    It 'ne dépend pas du module OffPatch' {
        $text = Get-Content -LiteralPath $resume -Raw -Encoding UTF8
        $text | Should -Not -Match 'Import-Module|OffPatch\.psd1|Get-Op[A-Z]|Write-OpLog'
    }
}
