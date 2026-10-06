@echo off
rem OffPatch : point d'entree (cahier des charges 8.1). Fichier en ASCII pur, fins de ligne CRLF.
rem 1. Choisit le PowerShell natif du systeme : depuis un cmd 32 bits sur Windows 64 bits
rem    (PROCESSOR_ARCHITEW6432 defini), passe par Sysnative au lieu de System32 (redirige vers SysWOW64).
rem 2. Si le processus n'est pas administrateur, demande l'elevation (UAC) et relance PowerShell eleve
rem    sur app\OffPatch.ps1 avec les memes arguments ; sinon lance directement.
rem Chemins : %~dp0 se termine par une barre oblique inverse. Elle n'est jamais placee juste avant un
rem guillemet (piege du \" a la racine d'un lecteur, %~dp0 = E:\) : le chemin passe a PowerShell finit
rem toujours par app\OffPatch.ps1, et la commande d'elevation est construite dans des variables
rem d'environnement, sans guillemets imbriques. Les accents et espaces du chemin sont conserves.
rem Essais seulement : OFFPATCH_LAUNCHER_DRYRUN = chemin d'un fichier ; la commande d'elevation y est
rem ecrite au lieu d'etre lancee. OFFPATCH_LAUNCHER_FORCE = elevate ou direct (pris en compte seulement
rem avec OFFPATCH_LAUNCHER_DRYRUN) force la branche, quel que soit le niveau reel des droits.
rem Ces deux variables sont ignorees hors d'un contexte de test : OFFPATCH_PESTER defini (tests Pester)
rem ou GITHUB_ACTIONS=true (runner GitHub).
setlocal
set "OFFPATCH_TESTCTX="
if defined OFFPATCH_PESTER set "OFFPATCH_TESTCTX=1"
if /i "%GITHUB_ACTIONS%"=="true" set "OFFPATCH_TESTCTX=1"
if not defined OFFPATCH_TESTCTX set "OFFPATCH_LAUNCHER_DRYRUN="
if not defined OFFPATCH_TESTCTX set "OFFPATCH_LAUNCHER_FORCE="
set "OFFPATCH_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "OFFPATCH_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "OFFPATCH_SCRIPT=%~dp0app\OffPatch.ps1"
set "OFFPATCH_ARGS=%*"

"%OFFPATCH_PS%" -NoProfile -NonInteractive -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
set "OFFPATCH_ADMIN=%errorlevel%"
if defined OFFPATCH_LAUNCHER_DRYRUN if /i "%OFFPATCH_LAUNCHER_FORCE%"=="elevate" set "OFFPATCH_ADMIN=1"
if defined OFFPATCH_LAUNCHER_DRYRUN if /i "%OFFPATCH_LAUNCHER_FORCE%"=="direct" set "OFFPATCH_ADMIN=0"
if "%OFFPATCH_ADMIN%"=="0" goto direct

rem Elevation : PowerShell construit la ligne de commande a partir des variables (aucun guillemet imbrique).
"%OFFPATCH_PS%" -NoProfile -NonInteractive -Command "$a = '-NoProfile -ExecutionPolicy Bypass -File ' + [char]34 + $env:OFFPATCH_SCRIPT + [char]34; if ($env:OFFPATCH_ARGS) { $a = $a + ' ' + $env:OFFPATCH_ARGS }; if ($env:OFFPATCH_LAUNCHER_DRYRUN) { [IO.File]::WriteAllText($env:OFFPATCH_LAUNCHER_DRYRUN, $env:OFFPATCH_PS + [char]10 + $a, (New-Object Text.UTF8Encoding $false)) } else { Start-Process -FilePath $env:OFFPATCH_PS -ArgumentList $a -Verb RunAs }"
if errorlevel 1 echo OffPatch : elevation refusee ou impossible. Relancez et acceptez la demande de l'administrateur.
exit /b %errorlevel%

:direct
"%OFFPATCH_PS%" -NoProfile -ExecutionPolicy Bypass -File "%OFFPATCH_SCRIPT%" %*
exit /b %errorlevel%
