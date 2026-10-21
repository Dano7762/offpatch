function Import-OpMainWindow {
    <#
    .SYNOPSIS
        Charge la fenêtre principale depuis MainWindow.xaml, sans l'afficher.

    .DESCRIPTION
        Cahier des charges 9. Le XAML est lu en UTF-8 et chargé par System.Windows.Markup.XamlReader : pas de
        compilation, pas de x:Class. Chaque élément nommé (x:Name) est retrouvé par FindName pour le câblage.
        Doit être appelé sur un thread STA (powershell.exe l'est par défaut). XAML absent ou invalide : exception.
        Renvoie Window et Controls (table nom -> élément).

    .PARAMETER Path
        Chemin du XAML ; par défaut MainWindow.xaml à côté de ce script.

    .EXAMPLE
        $ui = Import-OpMainWindow; [void]$ui.Window.ShowDialog()
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Path = (Join-Path $PSScriptRoot 'MainWindow.xaml')
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Interface WPF : thread STA requis (lancer powershell.exe sans -MTA).' }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    [xml]$xaml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
    $window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

    $controls = @{}
    $xNamespace = $xaml.DocumentElement.GetNamespaceOfPrefix('x')
    foreach ($node in @($xaml.SelectNodes('//*[@*[local-name()="Name"]]'))) {
        $name = $node.GetAttribute('Name', $xNamespace)
        if (-not $name) { $name = $node.GetAttribute('Name') }
        if ($name) { $controls[$name] = $window.FindName($name) }
    }
    [pscustomobject]@{ Window = $window; Controls = $controls }
}
