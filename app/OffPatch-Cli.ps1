<#
.SYNOPSIS
    OffPatch sans interface : mêmes opérations que l'interface, pour la reprise après redémarrage, le débogage et
    les tests.

.DESCRIPTION
    Charge le module, ouvre le journal, charge et valide la configuration, puis lance l'action demandée :
      - DepotUpdate -ListOnly : liste de ce qui serait téléchargé, liens contrôlés, espace libre ; code 1 si un lien
        est refusé. DepotUpdate : téléchargement, contrôle, manifeste, résumé des nouveautés ; code 1 si un lien est
        refusé ou si un élément n'a pas pu être inscrit ;
      - Plan : relevé du PC, contrôles préalables et plan, en lecture seule ;
      - InstallStep -StepId <id> : une étape du plan (refusée si elle n'est pas « À installer » ou si un contrôle
        préalable est bloquant) ; code 1 si elle est refusée ou en erreur ; le redémarrage nécessaire est signalé,
        jamais lancé ;
      - Report : rapport d'intervention de la session (étapes exécutées et plan du moment), puis fin de session ;
      - Auto : session automatique (plan affiché, une confirmation, étapes, redémarrages avec reprise, rapport) ;
        -Resume : reprise après redémarrage, sans confirmation (relancée par resume.ps1 via OffPatch.ps1) ;
        -ForceWindows : Windows 10 sans ESU actif, étapes Windows et .NET exécutées quand même (sinon ignorées) ;
      - Support -Destination <lecteur> : préparation d'un support (rapports rapatriés, outil et dépôt filtré copiés,
        manifeste filtré, puis vérification : tailles et SHA-256), avec -Targets et -OfficeSources (par défaut la
        sélection du dépôt) ; avec -WhatIf, plan de copie seul (contrôles, tailles) ; code 1 si le plan est refusé, si
        une copie échoue ou si la vérification trouve un écart.
    OffPatch installe uniquement des mises à jour : aucun paramètre de clé de produit, de profil ou de retrait
    (cahier des charges 2, 3.3).
    Codes de sortie : 0 réussite, 1 erreur (configuration invalide, étape refusée ou en échec).

.PARAMETER Action
    DepotUpdate : mise à jour du dépôt (avec -ListOnly : interroge sans rien télécharger).
    Plan : détection et plan pour ce PC, en lecture seule.
    InstallStep : exécution d'une étape du plan (-StepId).
    Report : écriture du rapport d'intervention.
    Auto : session automatique ; avec -Resume, reprise sans confirmation.
    Support : préparation d'un support (-Destination, -Targets, -OfficeSources).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Support -Destination F:\ -WhatIf

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action InstallStep -StepId <id>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('DepotUpdate', 'Plan', 'InstallStep', 'Report', 'Auto', 'Support')][string]$Action,
    [switch]$ListOnly,
    [string]$StepId,
    [switch]$Resume,
    [switch]$ForceWindows,
    [string]$Destination,
    [string[]]$Targets,
    [string[]]$OfficeSources
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module -Name (Join-Path $PSScriptRoot 'module\OffPatch\OffPatch.psd1') -Force -ErrorAction Stop
    $kind = 'Session'
    if (@('DepotUpdate', 'Support') -contains $Action) { $kind = 'Depot' }
    $context = Initialize-OpSession -Kind $kind -Root (Split-Path -Parent $PSScriptRoot) -Console
    Write-Host "Journal : $($context.Log.Path)"
} catch {
    Write-Host "OffPatch : $($_.Exception.Message)"
    exit 1
}

switch ($Action) {
    'DepotUpdate' {
        try {
            $result = Invoke-OpDepotUpdate -ListOnly:$ListOnly -Root $context.Root -WhatIf:$WhatIfPreference
            foreach ($line in Format-OpDepotPlan -Result $result) { Write-Host $line }
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if ($result.ErrorCount -gt 0) { exit 1 }
        exit 0
    }
    'Plan' {
        try {
            $info = Get-OpSystemInfo -Root $context.Root
            Write-Host "PC : $($info.ComputerName), $($info.Caption) $($info.DisplayVersion), build $($info.CurrentBuild).$($info.Ubr), cible $($info.Target)"
            Write-Host 'Contrôles préalables :'
            Write-Host (Test-OpPreflight -Root $context.Root -SystemInfo $info | Format-Table Label, Result, Message -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
            Write-Host 'Plan :'
            Write-Host (Get-OpInstallPlan -Root $context.Root -SystemInfo $info | Format-Table Sequence, Category, Id, State, RebootAfter, Reason -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        exit 0
    }
    'InstallStep' {
        if (-not $StepId) {
            Write-Host 'OffPatch : -StepId est obligatoire avec InstallStep (identifiant affiché par -Action Plan).'
            exit 1
        }
        try {
            $result = Invoke-OpInstallStep -StepId $StepId -Root $context.Root -WhatIf:$WhatIfPreference
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if (-not $result) { exit 0 }
        Write-Host "Étape $($result.Id) : $($result.State). $($result.Reason)"
        $reboot = $result.RebootAfter -or ($result.PSObject.Properties['RebootRequired'] -and $result.RebootRequired)
        if ($reboot) { Write-Host 'Redémarrage nécessaire avant l''étape suivante.' }
        if ($result.State -eq 'Error') { exit 1 }
        exit 0
    }
    'Report' {
        try {
            $path = Write-OpInstallReport -Root $context.Root -WhatIf:$WhatIfPreference
            if ($path) { Write-Host "Rapport : $path" }
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        exit 0
    }
    'Auto' {
        try {
            if (-not $Resume) {
                $info = Get-OpSystemInfo -Root $context.Root
                Write-Host 'Plan :'
                Write-Host (Get-OpInstallPlan -Root $context.Root -SystemInfo $info | Format-Table Sequence, Category, Id, State, RebootAfter, Reason -AutoSize -Wrap | Out-String -Width 200).TrimEnd()
            }
            $onStep = { param($s) if ($s.PSObject.Properties['Seconds']) { Write-Host "Étape $($s.Id) : $($s.State). $($s.Reason)" } else { Write-Host "Étape $($s.Id) ($($s.Category)) : en cours…" } }
            $onTick = { param($left) Write-Host "Redémarrage dans $left s (Ctrl+C pour interrompre)" }
            $confirm = @{}
            if ($Resume) { $confirm.Confirm = $false }
            $result = Invoke-OpAutoSession -Root $context.Root -OnStep $onStep -OnTick $onTick -ForceWindows:$ForceWindows -WhatIf:$WhatIfPreference @confirm
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if ($result) {
            Write-Host "Session automatique : $($result.Result)."
            if ($result.ReportPath) { Write-Host "Rapport : $($result.ReportPath)" }
        }
        exit 0
    }
    'Support' {
        if (-not $Destination) {
            Write-Host 'OffPatch : -Destination obligatoire avec -Action Support (racine du lecteur, par exemple F:\).'
            exit 1
        }
        $selection = @{}
        if ($PSBoundParameters.ContainsKey('Targets')) { $selection.Targets = $Targets }
        if ($PSBoundParameters.ContainsKey('OfficeSources')) { $selection.OfficeSources = $OfficeSources }
        try {
            $plan = Get-OpSupportPlan -Destination $Destination -Root $context.Root @selection
            Write-Host ('Support {0} : {1} élément(s) du dépôt, {2:N2} Go ; à copier {3:N2} Go.' -f $plan.Destination, @($plan.Items).Count, ($plan.DepotBytes / 1GB), ($plan.ToCopyBytes / 1GB))
            foreach ($w in $plan.Warnings) { Write-Host "Avertissement : $w" }
            foreach ($b in $plan.Blocking) { Write-Host "Refus : $b" }
            if (-not $plan.CanPrepare) { exit 1 }
            $result = Copy-OpSupport -Destination $Destination -Root $context.Root -WhatIf:$WhatIfPreference @selection
        } catch {
            Write-Host "OffPatch : $($_.Exception.Message)"
            exit 1
        }
        if (-not $result) { exit 0 }
        Write-Host ('Support {0} : {1} copie(s), {2} dossier(s) obsolète(s) supprimé(s){3}.' -f $result.Destination, @($result.Folders).Count, @($result.Removed).Count, $(if ($result.Cancelled) { ', préparation annulée' } else { '' }))
        if ($result.Cancelled) { exit 1 }
        $check = Test-OpSupport -Destination $result.Destination -Root $context.Root
        if (-not $check.Ok) {
            Write-Host "Vérification du support : $(@($check.Problems).Count) écart(s), support à ne pas utiliser en l'état."
            foreach ($p in $check.Problems) { Write-Host "  $p" }
            exit 1
        }
        Write-Host ('Vérification du support : {0} fichier(s) du dépôt conformes (tailles et SHA-256), outil complet, en {1:N0} s.' -f $check.FileCount, $check.Seconds)
        exit 0
    }
}
