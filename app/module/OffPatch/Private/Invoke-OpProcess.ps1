function Invoke-OpProcess {
    <#
    .SYNOPSIS
        Lance un programme et renvoie son code de sortie, ses sorties standard et d'erreur, sa durée.

    .DESCRIPTION
        Fonction unique de lancement de processus pour tous les exécuteurs (DISM, ODT, mpam-fe.exe, plateforme
        Defender), sur System.Diagnostics.Process : Start-Process est écarté, son ExitCode revenant vide sous
        Windows PowerShell 5.1 (R-14). Les sorties sont lues en parallèle de l'exécution, pour qu'un programme
        bavard ne se bloque pas sur un tampon plein. FilePath doit être un chemin complet (par exemple
        %SystemRoot%\System32\dism.exe, 8.4). Les arguments sont passés tels quels (ArgumentList, une chaîne par
        argument, mise entre guillemets si elle contient un espace ou un guillemet).
        TimeoutSeconds à 0 : pas de délai maximal (DISM, 8.4). Délai dépassé : le processus et ses processus enfants
        sont arrêtés (taskkill /T /F), TimedOut vaut vrai et ExitCode est nul.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
        [string]$WorkingDirectory
    )

    $quoted = foreach ($argument in $ArgumentList) {
        if ($argument -match '[\s"]') { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $argument }
    }
    $commandLine = @($quoted) -join ' '
    if (-not $PSCmdlet.ShouldProcess("$FilePath $commandLine", 'Lancement du processus')) { return }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $commandLine
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $started = Get-Date
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = $false
        if ($TimeoutSeconds -gt 0) {
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $timedOut = $true
                # Arrêt de toute l'arborescence : un processus enfant garderait les sorties ouvertes
                # (.NET Framework n'a pas de Kill(true)).
                $taskkill = New-Object System.Diagnostics.ProcessStartInfo
                $taskkill.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                $taskkill.Arguments = '/T /F /PID {0}' -f $process.Id
                $taskkill.UseShellExecute = $false
                $taskkill.CreateNoWindow = $true
                $killer = [System.Diagnostics.Process]::Start($taskkill)
                [void]$killer.WaitForExit(10000)
                $killer.Dispose()
                if (-not $process.HasExited) {
                    try { $process.Kill() } catch [System.InvalidOperationException] { $timedOut = $true }
                }
                [void]$process.WaitForExit(10000)
            }
        } else {
            $process.WaitForExit()
        }
        # Seconde attente sans délai : garantit la fin de la lecture des sorties redirigées.
        if (-not $timedOut) { $process.WaitForExit() }
        $exitCode = $null
        if (-not $timedOut) { $exitCode = $process.ExitCode }
        [void]$stdout.Wait(10000)
        [void]$stderr.Wait(10000)
        [pscustomobject]@{
            FilePath  = $FilePath
            Arguments = $commandLine
            ExitCode  = $exitCode
            TimedOut  = $timedOut
            StdOut    = $(if ($stdout.IsCompleted) { $stdout.Result } else { '' })
            StdErr    = $(if ($stderr.IsCompleted) { $stderr.Result } else { '' })
            Seconds   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    } finally {
        $process.Dispose()
    }
}
