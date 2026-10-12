function Test-OpPreflight {
    <#
    .SYNOPSIS
        Passe les contrôles préalables d'une session d'installation, en lecture seule, et renvoie un résultat par
        contrôle.

    .DESCRIPTION
        Cahier des charges 8.2, dans l'ordre du tableau. Chaque résultat porte Id, Label, Result (Ok, Warning ou
        Blocking), Message et Action (action proposée à l'interface ou au mode auto, $null sinon) :
          - Elevation : droits d'administrateur, bloquant ;
          - ProcessBitness : PowerShell 32 bits sur un Windows 64 bits, bloquant ;
          - Target : système dans le périmètre (3.1 ; builds de base de windows.supportedBuilds), sinon bloquant
            avec le motif ; avertissement si la cible n'est
            pas dans settings.json (rien au dépôt pour ce PC) ;
          - Esu (Windows 10) : ESU actif, sinon avertissement, Action SkipWindowsInAuto (R-04) ;
          - PendingReboot : redémarrage en attente (CBS, Windows Update, renommages), avertissement, Action
            ProposeReboot ;
          - FreeSpace : espace libre du volume système sous client.minFreeSpaceGB, bloquant ;
          - Battery : portable sur batterie, avertissement, Action ConfirmAutoMode ;
          - DepotAge : dépôt vide ou plus ancien que client.staleDepotWarningDays, avertissement ;
          - RestorePoint : avec createRestorePointBeforeSession, protection du système active (le point sera créé
            juste avant la première étape) ou avertissement ; jamais bloquant ;
          - Network : PC connecté à un réseau, avertissement qui recommande le mode Avion (R-15).
        Le contrôle d'intégrité des fichiers se fait juste avant chaque étape (8.4), pas ici. Rien n'est modifié.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .PARAMETER SystemInfo
        Relevé de Get-OpSystemInfo déjà fait ; relu sinon.

    .EXAMPLE
        Test-OpPreflight | Format-Table Label, Result, Message -AutoSize

    .EXAMPLE
        @(Test-OpPreflight | Where-Object Result -eq 'Blocking').Count -eq 0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root,
        [pscustomobject]$SystemInfo,
        [datetime]$Now = (Get-Date)
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    if (-not $SystemInfo) { $SystemInfo = Get-OpSystemInfo -Root $Root }
    $client = $configuration.Settings.client
    $i = $SystemInfo

    function ConvertTo-Check([string]$Id, [string]$Label, [string]$Result, [string]$Message, [string]$Action) {
        [pscustomobject]@{ Id = $Id; Label = $Label; Result = $Result; Message = $Message; Action = $Action }
    }
    # Lecture secondaire : résultat dans Value, ou message d'échec dans Error (le contrôle passe alors en
    # avertissement au lieu d'arrêter les autres).
    function Read-Safe([scriptblock]$Read) {
        try { [pscustomobject]@{ Value = @(& $Read); Error = $null } } catch { [pscustomobject]@{ Value = @(); Error = $_.Exception.Message } }
    }

    if (Test-OpElevated) { ConvertTo-Check 'Elevation' 'Droits administrateur' 'Ok' 'Session élevée.' $null }
    else { ConvertTo-Check 'Elevation' 'Droits administrateur' 'Blocking' 'OffPatch doit être lancé en administrateur (Lancer-OffPatch.cmd).' $null }

    if ($i.Is64BitOperatingSystem -and -not $i.Is64BitProcess) {
        ConvertTo-Check 'ProcessBitness' 'PowerShell natif' 'Blocking' 'PowerShell 32 bits sur un Windows 64 bits : DISM et le registre seraient vus à travers la redirection 32 bits. Lancer OffPatch par Lancer-OffPatch.cmd.' $null
    } else { ConvertTo-Check 'ProcessBitness' 'PowerShell natif' 'Ok' 'PowerShell natif du système.' $null }

    # Périmètre (3.1) : builds de base prises en charge par famille, dans windows.supportedBuilds.
    $family = $i.Family -replace '^Windows', 'win'
    $name = $i.Family -replace '^Windows', 'Windows '
    $supported = @()
    $builds = $configuration.Settings.windows.supportedBuilds
    if ($null -ne $builds.PSObject.Properties[$family]) { $supported = @($builds.$family | ForEach-Object { [int]$_ } | Sort-Object) }
    $label = "$($i.Caption) $($i.DisplayVersion), build $($i.CurrentBuild).$($i.Ubr), $($i.Architecture)"
    $reason = $null
    if ($i.ProductType -ne 1) { $reason = 'Windows Server' }
    elseif (@('x64', 'arm64') -notcontains $i.Architecture) { $reason = "architecture $($i.Architecture) non prise en charge" }
    elseif ($i.Family -eq 'Windows10' -and $i.Architecture -ne 'x64') { $reason = 'Windows 10 ARM64' }
    elseif ($supported -notcontains $i.CurrentBuild) {
        $list = 'aucune'
        if ($supported.Count -gt 0) { $list = $supported -join ', ' }
        if ($supported.Count -gt 0 -and $i.CurrentBuild -lt $supported[0]) { $reason = "$name antérieur aux versions prises en charge (builds $list)" }
        else { $reason = "version de $name non prise en charge (builds $list)" }
    }
    if ($reason) { ConvertTo-Check 'Target' 'Système pris en charge' 'Blocking' "Hors périmètre : $reason ($label)." $null }
    elseif (@($configuration.Settings.targets) -notcontains $i.Target) { ConvertTo-Check 'Target' 'Système pris en charge' 'Warning' "Cible $($i.Target) absente de settings.json : le dépôt ne contient rien pour ce PC ($label)." $null }
    else { ConvertTo-Check 'Target' 'Système pris en charge' 'Ok' "$label, cible $($i.Target)." $null }

    if ($i.Family -eq 'Windows10' -and $i.Esu) {
        if ($i.Esu.Status -eq 'Active') { ConvertTo-Check 'Esu' 'ESU Windows 10' 'Ok' "ESU actif (entreprise, année $($i.Esu.Year))." $null }
        else {
            $detail = ''
            if ($i.Esu.Detail) { $detail = " $($i.Esu.Detail)" }
            ConvertTo-Check 'Esu' 'ESU Windows 10' 'Warning' "ESU absent ou indétectable : en mode auto, l'étape Windows est ignorée sauf si elle est forcée dans le récapitulatif.$detail" 'SkipWindowsInAuto'
        }
    }

    $pending = Read-Safe { Get-OpPendingReboot }
    if ($pending.Error) { ConvertTo-Check 'PendingReboot' 'Redémarrage en attente' 'Warning' "Indicateurs illisibles. $($pending.Error)" $null }
    elseif ($pending.Value.Count -gt 0) { ConvertTo-Check 'PendingReboot' 'Redémarrage en attente' 'Warning' "Redémarrage en attente ($($pending.Value -join ', ')) : redémarrer avant de commencer." 'ProposeReboot' }
    else { ConvertTo-Check 'PendingReboot' 'Redémarrage en attente' 'Ok' 'Aucun redémarrage en attente.' $null }

    $min = [long]$client.minFreeSpaceGB * 1GB
    if ($null -eq $i.FreeSpaceBytes) { ConvertTo-Check 'FreeSpace' "Espace libre sur $($i.SystemDrive)" 'Blocking' "Espace libre de $($i.SystemDrive) illisible." $null }
    elseif ($i.FreeSpaceBytes -lt $min) { ConvertTo-Check 'FreeSpace' "Espace libre sur $($i.SystemDrive)" 'Blocking' ('{0:N1} Go libres, {1} Go demandés (minFreeSpaceGB).' -f ($i.FreeSpaceBytes / 1GB), $client.minFreeSpaceGB) $null }
    else { ConvertTo-Check 'FreeSpace' "Espace libre sur $($i.SystemDrive)" 'Ok' ('{0:N1} Go libres.' -f ($i.FreeSpaceBytes / 1GB)) $null }

    if ($i.Power -and $i.Power.OnBattery) {
        $charge = ''
        if ($null -ne $i.Power.BatteryPercent) { $charge = " ($($i.Power.BatteryPercent) %)" }
        ConvertTo-Check 'Battery' 'Alimentation' 'Warning' "Portable sur batterie$charge : brancher le secteur avant le mode auto." 'ConfirmAutoMode'
    } elseif (-not $i.Power) { ConvertTo-Check 'Battery' 'Alimentation' 'Warning' 'Alimentation illisible.' 'ConfirmAutoMode' }
    else { ConvertTo-Check 'Battery' 'Alimentation' 'Ok' 'Sur secteur ou sans batterie.' $null }

    $read = Read-Safe { Read-OpManifest -Path (Get-OpPath -Name Manifest -Root $Root) }
    $manifest = $read.Value | Select-Object -First 1
    if ($read.Error) { ConvertTo-Check 'DepotAge' 'Âge du dépôt' 'Warning' "Manifeste illisible. $($read.Error)" $null }
    elseif (@($manifest.items).Count -eq 0 -or -not $manifest.generatedAt) { ConvertTo-Check 'DepotAge' 'Âge du dépôt' 'Warning' 'Dépôt vide : rien à installer.' $null }
    else {
        $generated = [datetime]::Parse([string]$manifest.generatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        $days = [int][math]::Floor(($Now.ToUniversalTime() - $generated).TotalDays)
        if ($days -gt [int]$client.staleDepotWarningDays) { ConvertTo-Check 'DepotAge' 'Âge du dépôt' 'Warning' "Dépôt mis à jour il y a $days jours (au-delà de $($client.staleDepotWarningDays)) : des mises à jour plus récentes existent sans doute." $null }
        else { ConvertTo-Check 'DepotAge' 'Âge du dépôt' 'Ok' "Dépôt mis à jour il y a $days jour(s)." $null }
    }

    if (-not $client.createRestorePointBeforeSession) { ConvertTo-Check 'RestorePoint' 'Point de restauration' 'Ok' 'Désactivé dans settings.json (createRestorePointBeforeSession).' $null }
    else {
        $read = Read-Safe { Get-OpSystemProtection }
        $protection = $read.Value | Select-Object -First 1
        if ($read.Error) { ConvertTo-Check 'RestorePoint' 'Point de restauration' 'Warning' "Protection du système illisible : aucun point de restauration. $($read.Error)" $null }
        elseif ($protection.Active) { ConvertTo-Check 'RestorePoint' 'Point de restauration' 'Ok' 'Protection du système active : un point sera créé juste avant la première étape.' $null }
        else { ConvertTo-Check 'RestorePoint' 'Point de restauration' 'Warning' "Protection du système inactive sur $($i.SystemDrive) (SPP\Clients : $($protection.Spp), clichés réservés : $($protection.Storage)) : aucun point de restauration, OffPatch ne l'active jamais." $null }
    }

    $networks = Read-Safe { Get-OpNetworkConnection }
    if ($networks.Error) { ConvertTo-Check 'Network' 'Réseau' 'Warning' "État du réseau illisible : activer le mode Avion par précaution. $($networks.Error)" $null }
    elseif ($networks.Value.Count -gt 0) { ConvertTo-Check 'Network' 'Réseau' 'Warning' "PC connecté ($(@($networks.Value | ForEach-Object { "$($_.InterfaceAlias) : $($_.Connectivity)" }) -join ', ')) : Windows Update peut travailler en parallèle, activer le mode Avion pendant la session." $null }
    else { ConvertTo-Check 'Network' 'Réseau' 'Ok' 'PC hors ligne.' $null }
}
