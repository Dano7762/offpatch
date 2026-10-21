function Assert-OpNotCancelled {
    <#
    .SYNOPSIS
        Lève OperationCanceledException si l'annulation de l'opération en cours a été demandée.

    .DESCRIPTION
        Cahier des charges 9 : un téléchargement peut être annulé. Le jeton est posé par l'opération qui l'accepte
        (Invoke-OpDepotUpdate -CancellationToken) dans $script:OpCancellation, et consulté aux endroits où l'arrêt
        est propre : boucles de transfert (BITS suspendu, fichier .part gardé : reprise au lancement suivant), avant
        chaque fichier et chaque source Office. Sans jeton : rien.
    #>
    [CmdletBinding()]
    param()

    $token = $null
    if (Get-Variable -Name OpCancellation -Scope Script -ErrorAction SilentlyContinue) { $token = $script:OpCancellation }
    if ($token -and $token.IsCancellationRequested) { throw (New-Object System.OperationCanceledException 'Opération annulée à la demande.') }
}
