function Get-OpNetworkConnection {
    <#
    .SYNOPSIS
        Liste les réseaux auxquels le PC est connecté (nom du profil et connectivité).

    .DESCRIPTION
        Lecture seule (cahier des charges 8.2, R-15). Source : Get-NetConnectionProfile (module NetConnection), un
        profil par connexion réseau d'une carte physique. Un profil compte comme connecté si sa connectivité IPv4 ou
        IPv6 est Subnet, LocalNetwork ou Internet (ni Disconnected, ni NoTraffic). Mode Avion ou câble débranché :
        tableau vide. Renvoie Name, InterfaceAlias et Connectivity (la meilleure des deux).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $rank = @{ 'Subnet' = 1; 'LocalNetwork' = 2; 'Internet' = 3 }
    foreach ($p in @(Get-NetConnectionProfile -ErrorAction Stop)) {
        $best = @([string]$p.IPv4Connectivity, [string]$p.IPv6Connectivity | Where-Object { $rank.ContainsKey($_) } | Sort-Object { $rank[$_] } -Descending) | Select-Object -First 1
        if ($best) { [pscustomobject]@{ Name = [string]$p.Name; InterfaceAlias = [string]$p.InterfaceAlias; Connectivity = $best } }
    }
}
