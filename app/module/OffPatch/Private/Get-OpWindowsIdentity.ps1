function Get-OpWindowsIdentity {
    <#
    .SYNOPSIS
        Identifie la famille de Windows (10 ou 11), la build, l'UBR et le libellé du système.

    .DESCRIPTION
        Lecture seule. La famille se déduit de CurrentBuild (22000 et plus = Windows 11), jamais de ProductName :
        sur Windows 11, ProductName vaut encore « Windows 10 … » (R-09). Le libellé affiché vient de
        Win32_OperatingSystem.Caption. Architecture du système : x64, arm64 (ou la valeur Windows en minuscules).
        ProductType de Win32_OperatingSystem : 1 poste de travail, 2 contrôleur de domaine, 3 serveur.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $registry = Get-ItemProperty -Path $key -ErrorAction Stop
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

    $build = [int]$registry.CurrentBuild
    $family = 'Windows10'
    if ($build -ge 22000) { $family = 'Windows11' }

    $displayVersion = $null
    if ($registry.PSObject.Properties['DisplayVersion']) { $displayVersion = $registry.DisplayVersion }

    # Architecture du système, pas du processus : variable d'environnement machine PROCESSOR_ARCHITECTURE (AMD64,
    # ARM64, x86), lue dans le registre et non dans l'environnement du processus.
    $environment = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction Stop
    $architecture = $null
    if ($environment.PSObject.Properties['PROCESSOR_ARCHITECTURE']) {
        $architecture = switch ([string]$environment.PROCESSOR_ARCHITECTURE) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { $_.ToLowerInvariant() } }
    }

    [pscustomobject]@{
        Family         = $family
        CurrentBuild   = $build
        Ubr            = [int]$registry.UBR
        DisplayVersion = $displayVersion
        EditionId      = $registry.EditionID
        Caption        = $os.Caption
        Architecture   = $architecture
        ProductType    = [int]$os.ProductType
    }
}
