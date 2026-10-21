# Traitements longs de l'interface (cahier des charges 9, CLAUDE.md) : chaque traitement tourne dans un runspace à
# part, qui charge le module OffPatch ; il dépose ses messages dans une file (ConcurrentQueue, Write-OpLog via
# Initialize-OpSession -Queue) que le thread de l'interface vide par un DispatcherTimer. Le thread de l'interface
# n'attend jamais : il ne lit le résultat qu'une fois le traitement terminé.

function Start-OpBackgroundTask {
    <#
    .SYNOPSIS
        Lance un traitement long dans un runspace séparé, avec le module OffPatch chargé.

    .DESCRIPTION
        Le script reçoit ses paramètres (Parameters) et deux variables : $OpQueue, la file de messages de l'interface
        (à passer à Initialize-OpSession -Queue), et $OpCancel, le jeton d'annulation (CancellationToken) que le
        traitement consulte aux endroits où il peut s'arrêter proprement. Le script est transmis par son texte :
        il ne voit pas les variables de l'appelant.
        Renvoie la tâche (Queue, Cancellation, PowerShell, Handle, Runspace, Done), à passer à Receive-OpBackgroundTask.

    .PARAMETER ScriptBlock
        Traitement à exécuter.

    .PARAMETER Parameters
        Paramètres nommés du script.

    .PARAMETER ModulePath
        Manifeste du module OffPatch ; par défaut celui de l'outil.

    .EXAMPLE
        $task = Start-OpBackgroundTask -ScriptBlock { param($Root) $c = Initialize-OpSession -Kind Session -Queue $OpQueue -Root $Root; Get-OpInstallPlan -Root $Root } -Parameters @{ Root = $root }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [string]$ModulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'module\OffPatch\OffPatch.psd1')
    )

    if (-not $PSCmdlet.ShouldProcess('runspace', 'Lancement du traitement en arrière-plan')) { return }
    $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $cancellation = New-Object System.Threading.CancellationTokenSource
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ImportPSModule([string[]]@($ModulePath))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'OpQueue', $queue, 'File de messages de l''interface'))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'OpCancel', $cancellation.Token, 'Jeton d''annulation'))
    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($ScriptBlock.ToString()).AddParameters($Parameters)
    [pscustomobject]@{
        Queue        = $queue
        Cancellation = $cancellation
        PowerShell   = $ps
        Handle       = $ps.BeginInvoke()
        Runspace     = $runspace
        Done         = $false
    }
}

function Receive-OpBackgroundTask {
    <#
    .SYNOPSIS
        Relève, sans attendre, les messages d'un traitement et son résultat s'il est terminé.

    .DESCRIPTION
        Vide la file de messages. Si le traitement est terminé : lit sa sortie et ses erreurs (une erreur
        bloquante devient Error), libère le runspace et marque la tâche Done. Ne bloque jamais : appelé par le
        DispatcherTimer du thread de l'interface.
        Renvoie Messages, Completed, Output, Errors, Error (message de l'erreur bloquante) et Cancelled.

    .PARAMETER Task
        Tâche renvoyée par Start-OpBackgroundTask.

    .EXAMPLE
        $r = Receive-OpBackgroundTask -Task $task; foreach ($m in $r.Messages) { $m.Line }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Task
    )

    # Terminé avant de vider la file : aucun message déposé avant la fin n'est perdu.
    $completed = $Task.Done -or $Task.Handle.IsCompleted
    $messages = New-Object System.Collections.Generic.List[object]
    $message = $null
    while ($Task.Queue.TryDequeue([ref]$message)) { $messages.Add($message) }
    $result = [pscustomobject]@{
        Messages = $messages.ToArray(); Completed = $completed; Output = @(); Errors = @(); Error = $null
        Cancelled = $Task.Cancellation.IsCancellationRequested
    }
    if (-not $completed -or $Task.Done) { return $result }

    try {
        $result.Output = @($Task.PowerShell.EndInvoke($Task.Handle))
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        $result.Error = $inner.Message
    }
    $result.Errors = @($Task.PowerShell.Streams.Error | ForEach-Object { $_.ToString() })
    $Task.PowerShell.Dispose()
    $Task.Runspace.Dispose()
    $Task.Done = $true
    $result
}

function Stop-OpBackgroundTask {
    <#
    .SYNOPSIS
        Demande l'annulation d'un traitement en arrière-plan.

    .DESCRIPTION
        Annulation coopérative : le jeton $OpCancel du traitement passe à l'état annulé, et le traitement s'arrête au
        prochain endroit où il le consulte. Rien n'est interrompu de force : une étape DISM ou une installation en
        cours va jusqu'au bout (cahier des charges 9).

    .PARAMETER Task
        Tâche renvoyée par Start-OpBackgroundTask.

    .EXAMPLE
        Stop-OpBackgroundTask -Task $task
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][pscustomobject]$Task
    )

    if ($Task.Done) { return }
    if ($PSCmdlet.ShouldProcess('traitement en arrière-plan', 'Demande d''annulation')) { $Task.Cancellation.Cancel() }
}

function Register-OpBackgroundPump {
    <#
    .SYNOPSIS
        Relaie vers l'interface les messages et la fin d'un traitement, sur le thread de l'interface.

    .DESCRIPTION
        DispatcherTimer du Dispatcher du thread appelant (celui de la fenêtre) : à chaque intervalle,
        Receive-OpBackgroundTask ; OnMessage reçoit chaque message (Time, Level, Message, Line pour une ligne de
        journal), OnCompleted le résultat final (Output, Errors, Error, Cancelled), puis le minuteur s'arrête.
        Les deux blocs reçoivent Context en second argument (fenêtre, état) plutôt qu'une fermeture, qui les
        isolerait des fonctions du script. Ils tournent sur le thread de l'interface : ils peuvent modifier les contrôles directement.
        Renvoie le minuteur.

    .PARAMETER Task
        Tâche renvoyée par Start-OpBackgroundTask.

    .PARAMETER OnMessage
        Bloc appelé avec chaque message.

    .PARAMETER OnCompleted
        Bloc appelé une fois, avec le résultat final.

    .PARAMETER Context
        Objet transmis en second argument aux deux blocs (par exemple la fenêtre).

    .PARAMETER IntervalMilliseconds
        Intervalle de relève (200 ms par défaut).

    .EXAMPLE
        Register-OpBackgroundPump -Task $task -OnMessage { param($m) $log.AppendText($m.Line + "`n") } -OnCompleted { param($r) $button.IsEnabled = $true }
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Threading.DispatcherTimer])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Task,
        [scriptblock]$OnMessage,
        [scriptblock]$OnCompleted,
        [object]$Context,
        [ValidateRange(20, 5000)][int]$IntervalMilliseconds = 200
    )

    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [timespan]::FromMilliseconds($IntervalMilliseconds)
    # Tâche et blocs portés par le minuteur ($this dans le gestionnaire) : pas de fermeture, qui isolerait le
    # gestionnaire des fonctions de ce script.
    $timer.Tag = @{ Task = $Task; OnMessage = $OnMessage; OnCompleted = $OnCompleted; Context = $Context }
    $timer.Add_Tick({
            $context = $this.Tag
            $r = Receive-OpBackgroundTask -Task $context.Task
            foreach ($m in $r.Messages) { if ($context.OnMessage) { & $context.OnMessage $m $context.Context } }
            if ($r.Completed) {
                $this.Stop()
                if ($context.OnCompleted) { & $context.OnCompleted $r $context.Context }
            }
        })
    $timer.Start()
    $timer
}
