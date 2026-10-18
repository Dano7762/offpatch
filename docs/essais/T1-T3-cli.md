# Essais T1 et T3 en pilotant la CLI étape par étape (phase 4)

Déjà fait sans toi : actions `Plan` et `Report` sur le runner `windows-11-arm` (workflow `t3-plan`, aucune installation). Le reste demande des redémarrages et un Windows 11 x64 client : c'est une VM chez toi (VirtualBox), jetable grâce aux instantanés. On commence toujours par l'action `Plan`, en lecture seule.

## 0. Préparer le dépôt (poste de développement)

Le dépôt se construit comme chaque mois. PowerShell **en administrateur** (l'extraction de l'ODT l'exige, R-07), depuis la racine de l'outil :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action DepotUpdate
```

Attendu : code 0, résumé des nouveautés, `depot\manifest.json` écrit. Compte plusieurs gigaoctets (cumulatives des trois cibles, sources Office).

Fait le 18 octobre 2026 : dépôt complet, 0 erreur. `Plan` sur ton poste (25H2 à jour) a validé la détection ; T3 (« Windows 11 26H2 déjà à jour, rien à installer », cahier des charges 1.34) se fait à l'étape 4 ci-dessous, sur la VM T1 une fois toutes ses étapes passées.

## 1. Préparer la VM T1

1. VM Windows 11 **26H2 x64** installée depuis une ISO, **sans Office**, sans réseau (câble virtuel débranché : c'est le cas d'usage, et Windows Update ne travaille pas en parallèle).
2. Un second disque virtuel NTFS (le « support », par exemple `E:`), avec une copie de l'outil : `app\`, `config\`, `tools\`, `depot\`, `offpatch.root`, `Lancer-OffPatch.cmd`.
3. Instantané **« T1 vierge »** avant toute chose.

## 2. Plan en lecture seule

Dans la VM, PowerShell **en administrateur** :

```powershell
Set-Location E:\
$cli = '.\app\OffPatch-Cli.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli -Action Plan | Tee-Object -FilePath E:\T1-plan-1.txt
```

Attendu :

- contrôles préalables : droits administrateur `Ok`, système `Ok` (build 26300), aucun `Blocking` ; réseau sans avertissement (VM hors ligne) ;
- plan : plateforme et définitions Defender « Pending » (image de l'ISO plus ancienne que le dépôt), cumulative Windows 11 « Pending » avec `RebootAfter` vrai, enablement package « NotApplicable » (déjà en 26H2), .NET `KB5127694` (26H2) « Pending » ou « UpToDate » et `KB5127690` (24H2 et 25H2) « NotApplicable », motif « Build 26300 absente de baseBuilds », Office « NotApplicable » avec le motif « Aucun Office Click-to-Run. ».

**Envoie-moi `T1-plan-1.txt` avant d'aller plus loin** si quelque chose diffère.

## 3. Étapes une par une

Pour chaque ligne « Pending », **dans l'ordre du plan**, en reprenant l'identifiant de la colonne `Id` :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli -Action InstallStep -StepId <Id> | Tee-Object -FilePath E:\T1-etape-<n>.txt -Append
```

Attendu : `Étape <Id> : UpToDate.` et code 0. Si la sortie dit « Redémarrage nécessaire avant l'étape suivante. » : redémarre la VM (`Restart-Computer`), rouvre la session, relance l'étape 2 (`-Action Plan`, fichier `T1-plan-2.txt`, etc.) et reprends avec les lignes encore « Pending ». La CLI ne redémarre jamais elle-même.

Une étape en `Error` : ne pas insister, garde l'état de la VM et envoie-moi la sortie et le dossier `C:\ProgramData\OffPatch\logs` (journaux DISM et de session).

## 4. Fin et rapport

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli -Action Plan | Tee-Object -FilePath E:\T1-plan-final.txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli -Action Report
```

Attendu : plan final sans aucune ligne « Pending » ni « Error » (c'est T3 : un Windows 11 26H2 à jour, rien à installer) ; rapport `E:\rapports\AAAA-MM-JJ_<NomPC>_<Série>.html`, copie dans `C:\ProgramData\OffPatch\logs\`. Dans le rapport : Windows avant et après (UBR monté), versions Defender, Office « Non applicable : Aucun Office Click-to-Run. », chaque étape avec code retour et durée, rappel hors ligne (mode Avion ou réseau), point de restauration ou son motif (la protection du système est souvent inactive sur une VM : « Protection du système inactive », sans appel à `Checkpoint-Computer`).

## 5. À me renvoyer

- les fichiers `E:\T1-*.txt` ;
- le rapport HTML ;
- le dossier `C:\ProgramData\OffPatch\logs` (journal de session, sous-dossier avec les journaux DISM).

Rien de tout cela ne contient de clé ni de secret ; le numéro de série d'une VM VirtualBox est fictif.
