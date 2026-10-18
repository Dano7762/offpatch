<#
.SYNOPSIS
    Essai sur un runner GitHub : création réelle de la tâche OffPatch-Reprise par le module, relecture, suppression.

.DESCRIPTION
    Cahier des charges 8.6, R-18. Script réservé aux runners GitHub hébergés : il crée une tâche planifiée et écrit
    dans ProgramData. Register-OpResumeTask, puis Export-ScheduledTask (XML de la tâche) et Get-ScheduledTask :
    déclencheur, utilisateur, niveau d'exécution, réglages batterie, action ; resume.ps1 copié ; puis
    Unregister-OpResumeTask et contrôle de la disparition. Aucun redémarrage : le déclenchement à l'ouverture de
    session relève de l'intervention réelle (T1, T7).

.EXAMPLE
    .\Invoke-ResumeTaskTest.ps1 -OutputDirectory $env:RUNNER_TEMP\resume-task-out
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'Ce script crée une tâche planifiée : il ne s''exécute que sur un runner GitHub hébergé.'
}
if (-not $PSCmdlet.ShouldProcess('OffPatch-Reprise', 'Création, relecture et suppression de la tâche de reprise')) { return }

$toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$module = Import-Module -Name (Join-Path $toolRoot 'app\module\OffPatch\OffPatch.psd1') -Force -PassThru
$lines = & $module {
    param($Root, $Out)
    $lines = New-Object System.Collections.Generic.List[string]
    Start-OpLog -Kind Session -Directory (Join-Path $Out 'logs') | Out-Null
    $lines.Add('## Tâche OffPatch-Reprise sur runner')
    $lines.Add('')
    $lines.Add("- identité courante : $([Security.Principal.WindowsIdentity]::GetCurrent().Name) ; console : $((Get-CimInstance -ClassName Win32_ComputerSystem).UserName)")
    $r = Register-OpResumeTask -Root $Root -Confirm:$false
    $lines.Add("- utilisateur retenu : $($r.User) ; resume.ps1 copié : $(Test-Path -LiteralPath $r.ResumePath)")
    $task = Get-ScheduledTask -TaskName 'OffPatch-Reprise'
    $xml = Export-ScheduledTask -TaskName 'OffPatch-Reprise'
    $xml | Set-Content -LiteralPath (Join-Path $Out 'OffPatch-Reprise.xml') -Encoding UTF8
    $lines.Add("- état : $($task.State) ; déclencheur : $(@($task.Triggers)[0].CimClass.CimClassName), utilisateur $(@($task.Triggers)[0].UserId)")
    $lines.Add("- principal : $($task.Principal.UserId), $($task.Principal.LogonType), $($task.Principal.RunLevel)")
    $lines.Add("- batterie : DisallowStartIfOnBatteries $($task.Settings.DisallowStartIfOnBatteries), StopIfGoingOnBatteries $($task.Settings.StopIfGoingOnBatteries)")
    $lines.Add("- action : $(@($task.Actions)[0].Execute) $(@($task.Actions)[0].Arguments)")
    $again = Register-OpResumeTask -Root $Root -Confirm:$false
    $lines.Add("- seconde création (remplacement) : $(@(Get-ScheduledTask -TaskName 'OffPatch-Reprise').Count) tâche, utilisateur $($again.User)")
    $removed = Unregister-OpResumeTask -Confirm:$false
    $lines.Add("- suppression : $removed ; encore présente : $(@(Get-ScheduledTask -TaskName 'OffPatch-Reprise' -ErrorAction SilentlyContinue).Count -gt 0) ; seconde suppression : $(Unregister-OpResumeTask -Confirm:$false)")
    $lines
} $toolRoot $OutputDirectory
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'resume.md'), ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`r`n") -Encoding UTF8 }
