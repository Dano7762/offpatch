function Install-OpWindowsPackage {
    <#
    .SYNOPSIS
        Installe un paquet Windows ou .NET (DISM en ligne, wusa sur Windows 10) et juge le résultat sur la liste
        DISM, pas sur le seul code retour.

    .DESCRIPTION
        Cahier des charges 8.4 (R-02, R-14). Catégories windows-lcu, windows-checkpoint, windows-ekb, windows-ssu et
        dotnet. Avant l'étape, SHA-256 du fichier revérifié (écart : Error, DISM n'est pas lancé). Pour un élément .NET
        à plusieurs fichiers, le fichier est choisi par la valeur Release de .NET Framework 4 (netRelease), comme à la
        détection.
        Lancement : %SystemRoot%\System32\dism.exe /English /Online /Add-Package /PackagePath:<fichier> /NoRestart
        /LogPath:<LogDirectory>\dism_<id>.log, sans délai maximal. Élément Windows 10 (target.os win10) : DISM
        n'installe pas de .msu en ligne avant Windows 11 21H2 (R-19), d'où %SystemRoot%\System32\wusa.exe <fichier>
        /quiet /norestart, sans journal de l'étape (journal Setup de Windows) ; 2359302 (0x00240006, déjà installé,
        mesuré) est jugé comme 0.
          - 1618 ou 0x80070652 (autre installation en cours) : attente de RetryDelaySeconds, une seule nouvelle
            tentative, jugée comme la première.
          - Code autre que 0 ou 3010 (ou 2359302 avec wusa) : Error avec le code.
          - 0 ou 3010 : le paquet doit être Installed ou InstallPending dans la liste DISM (Get-WindowsPackage
            -Online) : cumulative et checkpoint par la version <build>.<resultingUbr> de Package_for_RollupFix,
            enablement package par son KB, .NET par le nom et la version du paquet lus dans le .msu. Sinon, journal
            avec « CBS HRESULT=0x800f081e » : NotApplicable et avertissement « jugé applicable par le planificateur » ;
            sans cette ligne : Error « DISM a réussi sans installer le paquet ». windows-ssu n'a pas de repère dans la
            liste : seule la ligne 0x800f081e est contrôlée.
        Le second temps du jugement (UBR après le redémarrage) relève de la reprise de session.
        Renvoie Id, Category, State (UpToDate, NotApplicable ou Error), Reason, ExitCode, RebootRequired (3010 ou
        paquet InstallPending), LogPath et Package (nom relevé dans la liste DISM).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Item,
        [Parameter(Mandatory)][string]$Depot,
        [Parameter(Mandatory)][string]$LogDirectory,
        [ValidateRange(0, 3600)][int]$RetryDelaySeconds = 300
    )

    $categories = 'windows-lcu', 'windows-checkpoint', 'windows-ekb', 'windows-ssu', 'dotnet'
    if ($categories -notcontains $Item.category) { throw "Install-OpWindowsPackage : catégorie $($Item.category) non prise en charge." }
    $busyCodes = 1618, -2147023278  # ERROR_INSTALL_ALREADY_RUNNING et 0x80070652 (R-14)
    $logPath = Join-Path $LogDirectory ('dism_{0}.log' -f ($Item.id -replace '[^\w.-]', '_'))

    function Get-Prop($Object, [string]$Name) {
        if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
        $null
    }
    function ConvertTo-StepResult([string]$State, [string]$Reason, $ExitCode, [bool]$Reboot, [string]$Package) {
        [pscustomobject]@{ Id = $Item.id; Category = $Item.category; State = $State; Reason = $Reason; ExitCode = $ExitCode; RebootRequired = $Reboot; LogPath = $logPath; Package = $Package }
    }
    function Format-Code($Code) {
        if ($null -eq $Code) { return 'absent' }
        '{0} (0x{1:X8})' -f $Code, ([int]$Code)
    }

    $files = @($Item.files)
    $file = $files[0]
    if (@($files | Where-Object { Get-Prop $_ 'netRelease' }).Count -gt 0) {
        $release = [int](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release
        $file = @($files | Where-Object { $r = Get-Prop $_ 'netRelease'; $r -and $release -ge [int]$r.min -and ($null -eq (Get-Prop $r 'max') -or $release -le [int]$r.max) }) | Select-Object -First 1
        if (-not $file) { return (ConvertTo-StepResult 'NotApplicable' "Aucun fichier de l'élément pour .NET Framework 4 Release $release." $null $false $null) }
    }

    $problems = @(Test-OpItemFileHash -Depot $Depot -File @($file))
    if ($problems.Count -gt 0) {
        $reason = "Fichier non conforme au manifeste, DISM non lancé : $($problems -join ' ')"
        Write-OpLog "$($Item.id) : $reason" -Level ERROR
        return (ConvertTo-StepResult 'Error' $reason $null $false $null)
    }
    $path = Join-Path $Depot ([string]$file.path -replace '/', '\')
    $engine = 'DISM'
    $exe = Join-Path $env:SystemRoot 'System32\dism.exe'
    $arguments = '/English', '/Online', '/Add-Package', "/PackagePath:$path", '/NoRestart', "/LogPath:$logPath"
    $successCodes = 0, 3010
    if ([string](Get-Prop (Get-Prop $Item 'target') 'os') -eq 'win10') {
        $engine = 'wusa'
        $exe = Join-Path $env:SystemRoot 'System32\wusa.exe'
        $arguments = $path, '/quiet', '/norestart'
        $successCodes = 0, 3010, 2359302
    }
    if (-not $PSCmdlet.ShouldProcess($path, "Installation par $engine en ligne")) { return }

    New-Item -ItemType Directory -Force -Path $LogDirectory -ErrorAction Stop | Out-Null
    $run = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Write-OpLog "$($Item.id) : $engine $(Split-Path -Leaf $path) (tentative $attempt)."
        $run = Invoke-OpProcess -FilePath $exe -ArgumentList $arguments -NoTimeout
        # Les lignes HOTPATCHUTIL de la console sont un diagnostic sans conséquence (R-14).
        $console = @(([string]$run.StdOut) -split '\r?\n' | Where-Object { $_.Trim() -and $_ -notmatch 'HOTPATCHUTIL' }) -join ' / '
        Write-OpLog "$($Item.id) : code retour $(Format-Code $run.ExitCode) en $($run.Seconds) s : $console"
        if ($attempt -eq 1 -and $busyCodes -contains $run.ExitCode) {
            Write-OpLog "$($Item.id) : une autre opération de maintenance est en cours ; nouvelle tentative dans $RetryDelaySeconds s." -Level WARN
            Start-Sleep -Seconds $RetryDelaySeconds
            continue
        }
        break
    }
    $code = $run.ExitCode
    if ($successCodes -notcontains $code) {
        $reason = "$engine a échoué, code $(Format-Code $code)."
        Write-OpLog "$($Item.id) : $reason" -Level ERROR
        return (ConvertTo-StepResult 'Error' $reason $code $false $null)
    }

    $found = $null
    if ($Item.category -ne 'windows-ssu') {
        try { $packages = @(Get-WindowsPackage -Online -ErrorAction Stop) }
        catch {
            $reason = "$engine a renvoyé $(Format-Code $code), liste des paquets illisible : $($_.Exception.Message)"
            Write-OpLog "$($Item.id) : $reason" -Level ERROR
            return (ConvertTo-StepResult 'Error' $reason $code ($code -eq 3010) $null)
        }
        $packages = @($packages | Where-Object { @('Installed', 'InstallPending') -contains [string]$_.PackageState })
        switch ($Item.category) {
            'windows-ekb' { $kb = [string]$Item.kb; $found = @($packages | Where-Object { $kb -and [string]$_.PackageName -like "*$kb*" }) | Select-Object -First 1 }
            'dotnet' {
                $wanted = [version]$file.package.version
                $found = @($packages | Where-Object {
                        $parts = [string]$_.PackageName -split '~'
                        $v = $null
                        $parts[0] -eq $file.package.name -and [version]::TryParse($parts[-1], [ref]$v) -and $v -ge $wanted
                    }) | Select-Object -First 1
            }
            default {
                $ubr = [int]$Item.resultingUbr
                $found = @($packages | Where-Object {
                        $parts = [string]$_.PackageName -split '~'
                        $v = $null
                        $parts[0] -eq 'Package_for_RollupFix' -and [version]::TryParse($parts[-1], [ref]$v) -and $v.Minor -eq $ubr
                    }) | Select-Object -First 1
            }
        }
    }

    $notApplicable = [bool](Select-String -LiteralPath $logPath -SimpleMatch 'CBS HRESULT=0x800f081e' -Quiet -ErrorAction SilentlyContinue)
    if ($found -or ($Item.category -eq 'windows-ssu' -and -not $notApplicable)) {
        $reboot = ($code -eq 3010) -or ($found -and [string]$found.PackageState -eq 'InstallPending')
        $name = $null
        if ($found) { $name = [string]$found.PackageName }
        $reason = 'Installé.'
        if ($found) { $reason = "$name : $($found.PackageState)." }
        if ($reboot) { $reason += ' Redémarrage nécessaire.' }
        Write-OpLog "$($Item.id) : $reason"
        return (ConvertTo-StepResult 'UpToDate' $reason $code $reboot $name)
    }
    if ($notApplicable) {
        Write-OpLog "$($Item.id) : paquet non applicable (CBS HRESULT=0x800f081e) alors qu'il a été jugé applicable par le planificateur : détection à corriger." -Level WARN
        return (ConvertTo-StepResult 'NotApplicable' 'Paquet non applicable à ce PC (CBS HRESULT=0x800f081e).' $code $false $null)
    }
    $reason = "$engine a réussi sans installer le paquet (code $(Format-Code $code))."
    Write-OpLog "$($Item.id) : $reason" -Level ERROR
    ConvertTo-StepResult 'Error' $reason $code $false $null
}
