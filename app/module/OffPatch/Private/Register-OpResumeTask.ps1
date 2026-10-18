function Register-OpResumeTask {
    <#
    .SYNOPSIS
        Prépare la reprise après redémarrage : copie resume.ps1 dans ProgramData et crée la tâche OffPatch-Reprise.

    .DESCRIPTION
        Cahier des charges 8.6 (avant un redémarrage). Module ScheduledTasks de Windows (Learn, consulté le
        2026-10-18, R-18) :
          - déclencheur à l'ouverture de session de l'utilisateur de la console (Win32_ComputerSystem.UserName), qui
            peut différer du compte élevé quand l'élévation s'est faite avec d'autres identifiants ; à défaut,
            l'identité courante ;
          - principal : cet utilisateur, LogonType Interactive (la tâche tourne dans sa session, l'interface y
            apparaît), RunLevel Highest (privilèges les plus élevés) ;
          - action : PowerShell natif du système, -File ProgramData\OffPatch\resume.ps1 ;
          - réglages : démarrage et poursuite sur batterie autorisés (sinon un portable débranché ne reprendrait pas).
        Une tâche du même nom est remplacée. Renvoie l'utilisateur retenu et le chemin de resume.ps1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$TaskName = 'OffPatch-Reprise'
    )

    $source = Join-Path $Root 'app\resume.ps1'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "resume.ps1 absent de $(Split-Path -Path $source -Parent) : reprise impossible." }
    $target = Get-OpPath -Name ClientResume
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $user = $null
    try { $user = [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName } catch { $user = $null }
    if (-not $user) {
        Write-OpLog "Utilisateur de la console illisible : la reprise est attachée à $current." -Level WARN
        $user = $current
    } elseif ($user -ne $current) {
        Write-OpLog "Session ouverte par $user, OffPatch élevé sous $current : la reprise est attachée à $user."
    }
    if (-not $PSCmdlet.ShouldProcess($TaskName, "Création de la tâche de reprise pour $user")) { return }

    New-Item -ItemType Directory -Force -Path (Split-Path -Path $target -Parent) -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $target)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-OpLog "Tâche $TaskName créée : ouverture de session de $user, privilèges les plus élevés, $target."
    [pscustomobject]@{ TaskName = $TaskName; User = $user; ResumePath = $target }
}
