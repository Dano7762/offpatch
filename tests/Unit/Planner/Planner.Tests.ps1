# Cas de planification P1 à P13 (cahier des charges 12) : détection (Get-OpUpdateState) puis plan (Get-OpInstallPlan)
# sur le manifeste de tests/Fixtures/planner/manifest.json et un relevé du PC par cas (tests/Fixtures/planner/cases).
# DISM, Defender et la valeur Release de .NET sont simulés ; rien n'est lu sur le PC réel.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables partagées entre blocs Pester, non vues par l''analyse.')]
param()

BeforeDiscovery {
    $fixtures = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Fixtures\planner'
    $cases = @(Get-ChildItem -Path (Join-Path $fixtures 'cases') -Filter '*.json' | Sort-Object { [int](($_.BaseName -split '-')[0].Substring(1)) }, Name | ForEach-Object {
            @{ Name = $_.BaseName; Path = $_.FullName }
        })
}

BeforeAll {
    Set-StrictMode -Version Latest
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $module = Join-Path $root 'app\module\OffPatch'
    foreach ($file in @(Get-ChildItem -Path (Join-Path $module 'Private'), (Join-Path $module 'Public') -Filter '*.ps1')) { . $file.FullName }

    $tool = Join-Path $TestDrive 'outil'
    New-Item -ItemType Directory -Force -Path $tool | Out-Null
    Copy-Item -Path (Join-Path $root 'config') -Destination $tool -Recurse
    Copy-Item -Path (Join-Path $root 'offpatch.root') -Destination $tool
    $manifest = Get-Content -LiteralPath (Join-Path $root 'tests\Fixtures\planner\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($f in @($manifest.items | ForEach-Object { $_.files })) {
        $p = Join-Path $tool ('depot\' + ($f.path -replace '/', '\'))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
        Set-Content -LiteralPath $p -Value 'x' -Encoding ASCII
    }

    # Valeurs par défaut d'un cas : Defender actif et à jour, .NET de Windows 11 installé, Release de .NET illisible.
    $defaults = @{
        defender     = [pscustomobject]@{ AMRunningMode = 'Normal'; AMProductVersion = '4.18.25090.3'; AntivirusSignatureVersion = '1.439.200.0' }
        dismPackages = @([pscustomobject]@{ PackageName = 'Package_for_DotNetRollup_481~31bf3856ad364e35~amd64~~10.0.9310.1'; PackageState = 'Installed' })
    }
    function Get-CaseValue($Case, [string]$Name) {
        if ($null -ne $Case.PSObject.Properties[$Name]) { return $Case.$Name }
        $defaults[$Name]
    }
}

Describe 'Plan d''installation : manifeste des cas' {
    It 'est un manifeste valide' {
        @(Test-OpManifest -Manifest $manifest) | Should -BeNullOrEmpty
    }
}

Describe 'Plan d''installation : cas <Name>' -ForEach $cases {
    BeforeAll {
        $case = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $exclude = @(Get-CaseValue $case 'excludeItems')
        $script:caseManifest = [pscustomobject]@{ schemaVersion = 1; generatedAt = $manifest.generatedAt; items = @($manifest.items | Where-Object { $exclude -notcontains $_.id }) }
        $script:caseDefender = Get-CaseValue $case 'defender'
        $script:caseDism = @(Get-CaseValue $case 'dismPackages')
        $script:caseRelease = Get-CaseValue $case 'netRelease'
        Mock Read-OpManifest { $script:caseManifest }
        Mock Get-MpComputerStatus { $script:caseDefender }
        Mock Get-WindowsPackage { $script:caseDism }
        Mock Get-ItemProperty -ParameterFilter { $Path -like '*NET Framework Setup*' } {
            if ($null -eq $script:caseRelease) { throw 'Release absent' }
            [pscustomobject]@{ Release = $script:caseRelease }
        }
        Mock Write-OpLog { }
        $plan = @(Get-OpInstallPlan -Root $tool -SystemInfo $case.systemInfo)
    }

    It 'donne les étapes attendues, dans l''ordre, avec leur état et leurs redémarrages' {
        @($plan | ForEach-Object { if ($_.Id) { $_.Id } else { $_.Category } }) | Should -Be @($case.expected | ForEach-Object { $_.step })
        $plan.State | Should -Be @($case.expected | ForEach-Object { $_.state })
        @($plan | Where-Object RebootAfter | ForEach-Object { if ($_.Id) { $_.Id } else { $_.Category } }) | Should -Be @($case.expected | Where-Object { $null -ne $_.PSObject.Properties['rebootAfter'] -and $_.rebootAfter } | ForEach-Object { $_.step })
    }

    # Chaque étape du plan passée à Invoke-OpInstallStep, exécuteurs simulés : seules les étapes à installer en appellent
    # un, celui de leur catégorie ; les autres sont refusées (P6 : DISM jamais lancé pour l'enablement package ignoré ;
    # P9, P11 : ODT jamais lancé).
    It 'n''exécute que les étapes à installer, chacune par l''exécuteur de sa catégorie' {
        $script:executed = New-Object System.Collections.Generic.List[string]
        $script:caseInfo = $case.systemInfo
        Mock Get-OpSystemInfo { $script:caseInfo }
        Mock Test-OpPreflight { }
        Mock New-OpRestorePoint { [pscustomobject]@{ Status = 'None'; Reason = 'simulé' } }
        Mock Get-OpPath { Join-Path $TestDrive "programdata\$Name" } -ParameterFilter { $Name -in 'ClientTemp', 'ClientLogs', 'State' }
        Mock Install-OpDefenderUpdate { $script:executed.Add("defender:$($Item.id)"); [pscustomobject]@{ Id = $Item.id; State = 'UpToDate'; Reason = '' } }
        Mock Install-OpWindowsPackage { $script:executed.Add("dism:$($Item.id)"); [pscustomobject]@{ Id = $Item.id; State = 'UpToDate'; Reason = '' } }
        Mock Install-OpOfficeUpdate { $script:executed.Add("odt:$($Item.id)"); [pscustomobject]@{ Id = $Item.id; State = 'UpToDate'; Reason = '' } }
        $executor = @{ 'defender-platform' = 'defender'; 'defender' = 'defender'; 'office-source' = 'odt' }
        Remove-Item -LiteralPath (Join-Path $TestDrive 'programdata') -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($step in @($plan | Where-Object { $_.Id })) {
            if ($step.State -eq 'Pending') { Invoke-OpInstallStep -StepId $step.Id -Root $tool | Out-Null }
            else { { Invoke-OpInstallStep -StepId $step.Id -Root $tool } | Should -Throw "*état $($step.State)*" -Because $step.Id }
        }
        $expected = @($plan | Where-Object { $_.State -eq 'Pending' } | ForEach-Object {
                $kind = $executor[$_.Category]
                if (-not $kind) { $kind = 'dism' }
                "${kind}:$($_.Id)"
            })
        @($script:executed) | Should -Be $expected
    }

    It 'donne le motif et la version attendus' {
        for ($i = 0; $i -lt @($case.expected).Count; $i++) {
            $e = @($case.expected)[$i]
            if ($null -ne $e.PSObject.Properties['reason']) { $plan[$i].Reason | Should -BeLike $e.reason -Because $e.step }
            if ($null -ne $e.PSObject.Properties['available']) { $plan[$i].Available | Should -Be $e.available -Because $e.step }
        }
    }
}
