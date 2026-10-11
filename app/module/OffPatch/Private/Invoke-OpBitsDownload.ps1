function Invoke-OpBitsDownload {
    <#
    .SYNOPSIS
        Télécharge un fichier par BITS, en reprenant le travail laissé par un lancement précédent.

    .DESCRIPTION
        Travail BITS asynchrone, nommé « OffPatch <fichier> » (cahier des charges 7.1, R-16) :
          - redirections refusées pendant le transfert (RedirectPolicyDisallow, posé par Set-BitsTransfer et relu ;
            s'il ne peut pas l'être, BITS est déclaré indisponible) : l'URL reçue est déjà l'URL finale, contrôlée par
            Resolve-OpDownloadUrl ; une redirection imprévue met le travail en erreur (HTTP 302) ;
          - un travail du même nom vers la même URL et le même fichier, laissé par un lancement interrompu, est repris
            (Resume-BitsTransfer) au lieu d'être recréé : BITS garde les octets déjà reçus ;
          - travail resté en file d'attente sans aucun octet reçu pendant QueuedSeconds (BITS ne transfère que pour
            un propriétaire en session interactive) : travail supprimé, erreur NotSupportedException « BITS
            indisponible », pour que l'appelant passe au repli HttpClient ;
          - erreur définitive (HTTP 404, redirection refusée…) : travail supprimé, erreur avec la description de BITS ;
          - aucun progrès pendant StallSeconds : travail laissé en place pour une reprise au prochain lancement, erreur.
        Le fichier n'apparaît à sa place qu'après Complete-BitsTransfer.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [ValidateRange(1, 3600)][int]$QueuedSeconds = 60,
        [ValidateRange(1, 86400)][int]$StallSeconds = 300,
        [ValidateRange(10, 60000)][int]$PollMilliseconds = 1000
    )

    if (-not $PSCmdlet.ShouldProcess($Destination, "Téléchargement BITS de $Url")) { return }
    try {
        Import-Module -Name BitsTransfer -ErrorAction Stop -Verbose:$false
    } catch {
        throw (New-Object System.NotSupportedException("BITS indisponible : module BitsTransfer non chargé ($($_.Exception.Message))."))
    }

    $displayName = 'OffPatch ' + [System.IO.Path]::GetFileName($Destination)
    $job = $null
    $resumed = $false
    foreach ($old in @(Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $displayName })) {
        $file = @($old.FileList) | Select-Object -First 1
        $same = $file -and $file.RemoteName -eq $Url -and $file.LocalName -eq $Destination -and @('Canceled', 'Acknowledged') -notcontains [string]$old.JobState
        if ($same -and -not $job) {
            $job = $old
            $resumed = $true
        } else {
            Remove-BitsTransfer -BitsJob $old -ErrorAction SilentlyContinue
        }
    }
    if ($job) {
        Write-OpLog "BITS : reprise du travail « $displayName » ($($job.BytesTransferred) octet(s) déjà reçus, état $($job.JobState))."
        if (@('Suspended', 'Error', 'TransientError') -contains [string]$job.JobState) { Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null }
    } else {
        # Start-BitsTransfer ignore -SecurityFlags (mesuré le 2026-10-11, R-16) : le travail est créé suspendu,
        # le refus des redirections posé par Set-BitsTransfer et relu, puis le transfert lancé.
        try {
            $job = Start-BitsTransfer -Source $Url -Destination $Destination -Asynchronous -Suspended -DisplayName $displayName -Description $Destination `
                -Priority Foreground -RetryInterval 60 -RetryTimeout ([Math]::Max(60, $StallSeconds)) -ErrorAction Stop
        } catch {
            throw (New-Object System.NotSupportedException("BITS indisponible : travail non créé ($($_.Exception.Message))."))
        }
        try {
            Set-BitsTransfer -BitsJob $job -SecurityFlags RedirectPolicyDisallow -ErrorAction Stop | Out-Null
            $flags = [string](Get-BitsTransfer -JobId $job.JobId -ErrorAction Stop).SecurityFlags
        } catch {
            $flags = $_.Exception.Message
        }
        if ($flags -ne 'RedirectPolicyDisallow') {
            Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
            throw (New-Object System.NotSupportedException("BITS indisponible : refus des redirections non appliqué ($flags)."))
        }
        Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null
    }

    $jobId = $job.JobId
    $started = Get-Date
    $lastBytes = [long]-1
    $lastProgress = Get-Date
    while ($true) {
        $job = Get-BitsTransfer -JobId $jobId -ErrorAction Stop
        $state = [string]$job.JobState
        $bytes = [long]$job.BytesTransferred
        if ($bytes -gt $lastBytes) { $lastBytes = $bytes ; $lastProgress = Get-Date }
        if ($state -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $job -ErrorAction Stop
            return [pscustomobject]@{ Path = $Destination; Engine = 'BITS'; Resumed = $resumed; SizeBytes = $bytes }
        }
        if ($state -eq 'Error') {
            $detail = ("$($job.ErrorDescription)" -replace '\s+', ' ').Trim() + " (contexte $($job.ErrorContext))"
            Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
            throw "Téléchargement BITS en échec, $Url : $detail"
        }
        if ($state -eq 'Queued' -and $bytes -le 0 -and ((Get-Date) - $started).TotalSeconds -ge $QueuedSeconds) {
            Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
            throw (New-Object System.NotSupportedException("BITS indisponible : travail resté en file d'attente $QueuedSeconds s sans transfert (session non interactive ?)."))
        }
        if (((Get-Date) - $lastProgress).TotalSeconds -ge $StallSeconds) {
            throw "Téléchargement BITS sans progrès depuis $StallSeconds s ($state, $bytes octet(s) reçus), $Url : travail « $displayName » conservé, reprise au prochain lancement."
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
}
