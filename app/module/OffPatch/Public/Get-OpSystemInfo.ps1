function Get-OpSystemInfo {
    <#
    .SYNOPSIS
        Relève, en lecture seule, l'état du PC : Windows, ESU, Office, espace libre, alimentation et matériel.

    .DESCRIPTION
        Face Installation (cahier des charges 8.2, 8.3, 8.8, 9). Rien n'est modifié sur le PC.
          - Windows (Get-OpWindowsIdentity) : famille d'après CurrentBuild, libellé, édition, version, build, UBR,
            architecture du système ; Target, nom de cible au format de settings.json (win11-x64…), sans jugement sur
            sa prise en charge, laissé aux contrôles préalables.
          - Processus : Is64BitOperatingSystem et Is64BitProcess (PowerShell 32 bits sur Windows 64 bits, 8.2).
          - ESU, pour Windows 10 seulement (R-04) : Active, avec l'année, si la classe WMI SoftwareLicensingProduct
            porte l'un des identifiants de windows.esuActivationIds avec LicenseStatus 1 ; sinon Undetectable (ESU
            grand public sans trace hors ligne connue, ou requête en échec, motif dans Detail).
          - Office (Get-OpOfficeInstallation) : produits, langues, canal, version ; $null sans Office Click-to-Run.
          - Espace libre du volume système, alimentation (Get-OpPowerStatus), fabricant, modèle, numéro de série
            BIOS. Une lecture secondaire en échec (WMI, alimentation) laisse sa valeur à $null sans arrêter le relevé.

    .PARAMETER Root
        Racine de l'outil ; par défaut, celle retrouvée par le fichier offpatch.root.

    .EXAMPLE
        Get-OpSystemInfo

    .EXAMPLE
        (Get-OpSystemInfo).Office | Format-List
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Root
    )

    if (-not $Root) { $Root = Get-OpRoot }
    $configuration = Get-OpConfiguration -Root $Root
    $identity = Get-OpWindowsIdentity

    function Get-Optional([scriptblock]$Read) {
        try { & $Read } catch { Write-Verbose "Lecture impossible : $($_.Exception.Message)"; $null }
    }
    $computer = Get-Optional { Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer, Model -ErrorAction Stop }
    $bios = Get-Optional { Get-CimInstance -ClassName Win32_BIOS -Property SerialNumber -ErrorAction Stop }

    $target = $null
    if ($identity.Architecture) { $target = '{0}-{1}' -f ($identity.Family -replace '^Windows', 'win'), $identity.Architecture }

    $esu = $null
    if ($identity.Family -eq 'Windows10') {
        $esu = [pscustomobject]@{ Status = 'Undetectable'; Year = $null; Detail = $null }
        $ids = @()
        if ($null -ne $configuration.Settings.windows.PSObject.Properties['esuActivationIds']) { $ids = @($configuration.Settings.windows.esuActivationIds | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
        if ($ids.Count -gt 0) {
            try {
                $filter = (@($ids | ForEach-Object { "ID='$_'" }) -join ' OR ')
                $licensed = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $filter -Property ID, LicenseStatus -ErrorAction Stop | Where-Object { [int]$_.LicenseStatus -eq 1 })
                $years = @($licensed | ForEach-Object { [array]::IndexOf($ids, ([string]$_.ID).ToLowerInvariant()) + 1 } | Where-Object { $_ -gt 0 } | Sort-Object)
                if ($years.Count -gt 0) {
                    $esu.Status = 'Active'
                    $esu.Year = $years[-1]
                }
            } catch {
                $esu.Detail = "Licence ESU illisible : $($_.Exception.Message)"
            }
        } else {
            $esu.Detail = 'Aucun identifiant ESU dans settings.json (windows.esuActivationIds).'
        }
    }

    $manufacturer = $null; $model = $null; $serial = $null
    if ($computer) { $manufacturer = ([string]$computer.Manufacturer).Trim(); $model = ([string]$computer.Model).Trim() }
    if ($bios) { $serial = ([string]$bios.SerialNumber).Trim() }

    [pscustomobject]@{
        ComputerName           = $env:COMPUTERNAME
        Manufacturer           = $manufacturer
        Model                  = $model
        SerialNumber           = $serial
        Family                 = $identity.Family
        Caption                = $identity.Caption
        EditionId              = $identity.EditionId
        DisplayVersion         = $identity.DisplayVersion
        CurrentBuild           = $identity.CurrentBuild
        Ubr                    = $identity.Ubr
        Architecture           = $identity.Architecture
        Target                 = $target
        ProductType            = $identity.ProductType
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
        Is64BitProcess         = [Environment]::Is64BitProcess
        Esu                    = $esu
        Office                 = Get-OpOfficeInstallation
        SystemDrive            = $env:SystemDrive
        FreeSpaceBytes         = Get-OpFreeSpace -Path "$($env:SystemDrive)\"
        Power                  = Get-Optional { Get-OpPowerStatus }
    }
}
