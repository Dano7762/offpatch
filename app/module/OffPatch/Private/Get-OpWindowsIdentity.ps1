function Get-OpWindowsIdentity {
    <#
    .SYNOPSIS
        Identifie la famille de Windows (10 ou 11), la build, l'UBR et le libellé du système.

    .DESCRIPTION
        Lecture seule. La famille se déduit de CurrentBuild (22000 et plus = Windows 11), jamais de ProductName :
        sur Windows 11, ProductName vaut encore « Windows 10 … » (R-09). Le libellé affiché vient de
        Win32_OperatingSystem.Caption.
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

    [pscustomobject]@{
        Family         = $family
        CurrentBuild   = $build
        Ubr            = [int]$registry.UBR
        DisplayVersion = $displayVersion
        EditionId      = $registry.EditionID
        Caption        = $os.Caption
    }
}
