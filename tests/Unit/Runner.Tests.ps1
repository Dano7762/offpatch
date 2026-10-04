# Garde-fous des scripts de tests/runner. Aucun accès réseau, aucune modification du système.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeAll {
    $runner = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tests\runner'
}

Describe 'Invoke-R02CheckpointTest.ps1' {
    BeforeEach {
        $savedFlag = $env:GITHUB_ACTIONS
    }
    AfterEach {
        $env:GITHUB_ACTIONS = $savedFlag
    }

    It 'refuse de s''exécuter hors d''un runner GitHub' {
        $env:GITHUB_ACTIONS = 'false'
        { & (Join-Path $runner 'Invoke-R02CheckpointTest.ps1') -Kb 'KB0000000' -OutputDirectory $TestDrive -WhatIf } |
            Should -Throw -ExpectedMessage '*runner GitHub*'
    }

    It 'déclare SupportsShouldProcess' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $runner 'Invoke-R02CheckpointTest.ps1'), [ref]$null, [ref]$null)
        $attribute = $ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        ($attribute.NamedArguments | Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Save-CatalogEntryFile.ps1' {
    It 'rejette un numéro de KB mal formé avant tout accès réseau' {
        { & (Join-Path $runner 'Save-CatalogEntryFile.ps1') -Kb '5129195' -Destination $TestDrive -ListOnly } |
            Should -Throw
    }

    It 'rejette une architecture inconnue' {
        { & (Join-Path $runner 'Save-CatalogEntryFile.ps1') -Kb 'KB5129195' -Arch 'x86' -Destination $TestDrive -ListOnly } |
            Should -Throw
    }
}

Describe 'Test-PinnedFile.ps1' {
    It 'refuse un domaine non autorisé avant tout téléchargement' {
        { & (Join-Path $runner 'Test-PinnedFile.ps1') -Url 'https://example.com/Windows11.0-KB0000000-x64_0000000000000000000000000000000000000000.msu' -Destination $TestDrive -ReportPath (Join-Path $TestDrive 'r.json') } |
            Should -Throw -ExpectedMessage '*non autorisé*'
    }

    It 'refuse un lien non HTTPS' {
        { & (Join-Path $runner 'Test-PinnedFile.ps1') -Url 'http://catalog.sf.dl.delivery.mp.microsoft.com/x/Windows11.0-KB0000000-x64_0000000000000000000000000000000000000000.msu' -Destination $TestDrive -ReportPath (Join-Path $TestDrive 'r.json') } |
            Should -Throw -ExpectedMessage '*non autorisé*'
    }
}

Describe 'Invoke-R06DefenderTest.ps1' {
    BeforeEach { $savedFlag = $env:GITHUB_ACTIONS }
    AfterEach { $env:GITHUB_ACTIONS = $savedFlag }

    It 'refuse de s''exécuter hors d''un runner GitHub' {
        $env:GITHUB_ACTIONS = 'false'
        { & (Join-Path $runner 'Invoke-R06DefenderTest.ps1') -OutputDirectory $TestDrive -WhatIf } |
            Should -Throw -ExpectedMessage '*runner GitHub*'
    }
}

Describe 'Invoke-R07OfficeSourceTest.ps1' {
    BeforeEach { $savedFlag = $env:GITHUB_ACTIONS }
    AfterEach { $env:GITHUB_ACTIONS = $savedFlag }

    It 'refuse de s''exécuter hors d''un runner GitHub' {
        $env:GITHUB_ACTIONS = 'false'
        { & (Join-Path $runner 'Invoke-R07OfficeSourceTest.ps1') -Channel 'PerpetualVL2024' -ProductId 'ProPlus2024Volume' -OutputDirectory $TestDrive } |
            Should -Throw -ExpectedMessage '*runner GitHub*'
    }

    It 'rejette un canal contenant des caractères non attendus' {
        { & (Join-Path $runner 'Invoke-R07OfficeSourceTest.ps1') -Channel 'Current" /x' -ProductId 'ProPlus2024Volume' -OutputDirectory $TestDrive } |
            Should -Throw
    }
}
