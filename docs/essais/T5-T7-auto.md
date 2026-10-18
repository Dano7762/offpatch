# Essais T5 et T7 en mode automatique sur la VM Windows 10 (phase 5)

VM de David : Windows 10 22H2 x64, build 19045.2965, sans ESU, sans Office. C'est exactement T5 (« Windows 10 22H2 sans ESU : avertissement, aucune étape Windows en mode auto »). T7 (support débranché pendant un redémarrage) demande une étape réussie suivie d'un redémarrage : sans ESU, le mode auto n'en a pas (la seule étape qui redémarre est la cumulative Windows, ignorée) ; d'où le second passage forcé de l'étape 4. T1 et T2 restent à faire sur une VM Windows 11.

Le mode automatique tourne pour l'instant en console : `Lancer-OffPatch.cmd` demande l'élévation, lance `app\OffPatch.ps1`, qui affiche le plan et demande une confirmation, puis enchaîne tout seul. L'interface WPF le remplacera en phase 6. On commence toujours par l'action `Plan`, en lecture seule.

## 1. Préparer la VM et le support

1. VM **sans réseau** (câble virtuel débranché).
2. Support : pour T7, une **clé USB réelle** passée à la VM (VirtualBox, menu Périphériques > USB), formatée en NTFS, car il faudra la débrancher. Copie de l'outil à sa racine, depuis la dernière version du dépôt git : `app\`, `config\`, `tools\`, `depot\`, `offpatch.root`, `Lancer-OffPatch.cmd`. Le dépôt du 18 octobre contient déjà les éléments Windows 10 (cumulative, SSU, .NET, Defender). Une deuxième clé USB quelconque sert au test de changement de lettre.
3. Instantané **« T5 vierge »** de la VM, clé branchée.

Dans la suite, `E:` désigne la lettre de la clé dans la VM : remplace-la par la vraie.

## 2. Plan en lecture seule

PowerShell **en administrateur** dans la VM :

```powershell
Set-Location E:\
$cli = '.\app\OffPatch-Cli.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli -Action Plan | Tee-Object -FilePath E:\T5-plan-1.txt
```

Attendu :

- contrôles préalables : aucun `Blocking` ; « ESU Windows 10 » en `Warning`, « ESU absent ou indétectable : en mode auto, les étapes Windows et .NET sont ignorées sauf si elles sont forcées dans le récapitulatif » ; réseau `Ok` (PC hors ligne) ;
- plan : SSU `win10-x64-ssu-KB5031539` « Pending » (UBR 2965 sous 3271), cumulative `win10-x64-lcu-KB5126657` « Pending » avec `RebootAfter` vrai, .NET `win10-x64-dotnet-KB5128925` « Pending » ou « NotApplicable » selon la version de .NET 4.x de l'image, plateforme et définitions Defender « Pending ».

**Envoie-moi `T5-plan-1.txt` avant d'aller plus loin** si quelque chose diffère (surtout un `Blocking`).

## 3. T5 : mode automatique sans forçage

Double-clic sur `E:\Lancer-OffPatch.cmd`, accepter l'élévation. Dans la console :

1. le plan s'affiche, puis une question de confirmation « Démarrage de la session automatique » : répondre **O** (Oui) ;
2. les étapes défilent : `Étape … (catégorie) : en cours…` puis `Étape … : UpToDate.` ;
3. fin : `Session automatique : Completed.`, chemin du rapport, puis « Appuyer sur Entrée pour fermer ».

Attendu :

- aucune étape `windows-ssu`, `windows-lcu` ni `dotnet` exécutée (ESU absent, R-19) ; Defender (plateforme puis définitions) exécuté, chacun `UpToDate` ;
- **aucun redémarrage** ;
- rapport `E:\rapports\AAAA-MM-JJ_<NomPC>_<Série>.html` : cumulative et SSU toujours « Pending » ; dans les avertissements du journal, deux lignes « Étape … ignorée : ESU absent ou indétectable, étape Windows non forcée en mode auto. » ; rappel hors ligne (mode Avion ou réseau) ;
- dans `C:\ProgramData\OffPatch\` : plus de `state.json`, de `resume.ps1` ni de `temp\` ; `logs\` contient le journal de session, l'archive `state_*.json` et la copie du rapport ;
- `Get-ScheduledTask -TaskName OffPatch-Reprise` : erreur « aucune tâche » (attendu).

Garde le contenu de la console : copie-le dans `E:\T5-console.txt` (sélection puis Entrée).

## 4. T7 : redémarrage avec support débranché (passage forcé)

Revenir à l'instantané **« T5 vierge »**. PowerShell **en administrateur** :

```powershell
Set-Location E:\
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Auto -ForceWindows
```

Répondre **O** à la confirmation. La SSU s'installe d'abord, puis la cumulative ESU. Microsoft ne la destine qu'aux PC inscrits à l'ESU : on ne sait pas si DISM l'accepte sur ce PC, et l'essai nous le dira (utile pour R-04).

- **Si la cumulative échoue** (`Error`, retentée une fois, puis « abandonnée après deux échecs ») : la session continue avec .NET et Defender et finit par le rapport, sans redémarrage. T7 ne peut pas se faire sur cette VM : envoie-moi la console et `C:\ProgramData\OffPatch\logs` (journal DISM de l'étape), et on passera à la VM Windows 11.
- **Si elle réussit** (`UpToDate`) : compte à rebours « Redémarrage dans 30 s », puis la VM redémarre. Ensuite :
  1. dès que la VM est éteinte ou sur l'écran de connexion, **débranche la clé** (menu USB de VirtualBox) ;
  2. ouvre la session : une petite fenêtre « OffPatch » demande de rebrancher le support ; attends une quinzaine de secondes ;
  3. branche d'abord **l'autre clé USB** (elle prend la lettre `E:`), puis la clé OffPatch (elle prend `F:` ou une autre lettre) ;
  4. attendu : dans les 5 secondes, la fenêtre se ferme, une console OffPatch s'ouvre et reprend **sans question**, avec les étapes restantes (.NET, Defender), puis `Completed` et le rapport, écrit sur la clé, sous sa nouvelle lettre.

Contrôles après T7 : mêmes contrôles de fin qu'en T5. Dans le rapport, Windows « après » à un UBR supérieur à 2965, un redémarrage compté. Le journal `C:\ProgramData\OffPatch\logs\resume_*.log` doit montrer « Support introuvable … attente du rebranchement », puis « Support rebranché après … s » et « Support trouvé : F:\ ».

## 5. À me renvoyer

- `E:\T5-plan-1.txt`, `E:\T5-console.txt` et, pour T7, la sortie de la console ;
- les rapports HTML (`rapports\`) ;
- le dossier `C:\ProgramData\OffPatch\logs` après chaque passage (journaux de session, de reprise et DISM).

Rien de tout cela ne contient de clé ni de secret ; le numéro de série d'une VM VirtualBox est fictif.
