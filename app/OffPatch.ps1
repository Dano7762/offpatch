<#
.SYNOPSIS
    Point d'entrée d'OffPatch : lance l'interface WPF. Lancé par Lancer-OffPatch.cmd et, avec -Resume, par
    resume.ps1 après un redémarrage.

.DESCRIPTION
    Cahier des charges 8.1, 8.6, 9. Charge le module, ouvre le journal, retire la marque « fichier téléchargé » des
    fichiers de l'outil, charge la fenêtre et câble l'en-tête et les trois onglets. Avec -Resume, la session
    automatique en cours (state.json) reprend d'elle-même une fois le relevé du PC fait, sans question.
    Démarrage impossible (configuration invalide, fenêtre illisible) : message, code de sortie 1.

.PARAMETER Resume
    Reprise de la session automatique en cours (state.json), sans confirmation.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch.ps1
#>
[CmdletBinding()]
param(
    [switch]$Resume
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot 'module\OffPatch\OffPatch.psd1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    [void](Initialize-OpSession -Kind Session -Root $root -Unblock)
    foreach ($name in 'MainWindow', 'Background', 'Header', 'PcTab', 'DepotTab', 'LogTab', 'Dialogs\AutoSummary') { . (Join-Path $PSScriptRoot "gui\$name.ps1") }
    $ui = Import-OpMainWindow
    Show-OpHeader -Controls $ui.Controls -Status (Get-OpDepotStatus -Root $root)
    Register-OpPcTab -Ui $ui -Root $root -ModulePath $modulePath -Resume:$Resume
    Register-OpDepotTab -Ui $ui -Root $root -ModulePath $modulePath
    Register-OpLogTab -Ui $ui -Root $root
} catch {
    $message = "OffPatch ne peut pas démarrer : $($_.Exception.Message)"
    Write-Host $message
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [void][System.Windows.MessageBox]::Show($message, 'OffPatch', 'OK', 'Error')
    } catch {
        [void](Read-Host 'Appuyer sur Entrée pour fermer')
    }
    exit 1
}
[void]$ui.Window.ShowDialog()
