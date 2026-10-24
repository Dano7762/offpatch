# Essais T8 puis T5 sur un support préparé (phase 7)

T8 (« préparation d'un support en FAT32 : refus avec message explicite ») tourne d'abord sur un runner GitHub (`t8-support.yml` : disques virtuels FAT32, exFAT et NTFS, dépôt synthétique de 8 Mo), puis sur une vraie clé USB. Ensuite, la clé préparée par l'assistant sert à refaire T5 sur la VM Windows 10 : le manifeste filtré et la vérification sont ainsi validés jusqu'au PC client.

T4 (ESU actif) et T6 (Windows 11 ARM64 avec Office) demandent un PC inscrit à l'ESU et un PC ARM64 avec un Office Click-to-Run : ni l'un ni l'autre n'est disponible (décisions du 2026-10-21 sur R-04 et sur la partie Office de T2). Ils restent à valider chez un client ou à trancher en phase 8, avec T1.

## 1. T8 sur le runner

Après le push : `gh workflow run t8-support.yml`. Attendu dans le résumé du run :

- FAT32 : code 1, « Refus : Système de fichiers FAT32 refusé : NTFS ou exFAT requis (en FAT32, un fichier ne peut pas dépasser 4 Gio, et la cumulative Windows 11 x64 les dépasse). », rien d'écrit sur le disque ;
- exFAT et NTFS : plan accepté, copie, vérification « conforme ».

## 2. T8 sur une vraie clé

Sur ton PC, avec une clé USB de 32 Go au plus **dont le contenu peut être effacé** :

1. formater la clé en **FAT32** (Explorateur, clic droit > Formater) ;
2. lancer `Lancer-OffPatch.cmd`, onglet Dépôt, « Préparer un support… », choisir la clé ;
3. attendu : contrôle du système de fichiers en refus avec le message ci-dessus, bouton « Préparer le support » grisé ; rien n'est écrit sur la clé (elle reste vide) ;
4. fermer l'assistant, reformater la clé en **exFAT**, rouvrir l'assistant ou cliquer « Actualiser » ;
5. ne garder que la cible **win10-x64**, aucune source Office ; attendu : contrôles acceptés, taille de quelques Go ;
6. « Préparer le support », confirmer : avancement dossier par dossier, puis bilan « support prêt » (tailles et SHA-256 vérifiés).

Capture d'écran du refus (étape 3) et du bilan (étape 6).

## 3. T5 depuis la clé préparée

Le passage USB de VirtualBox fausse les lectures du dépôt : la clé reste branchée sur l'hôte, sans être attribuée à la VM, et la VM la lit par un dossier partagé.

1. VM Windows 10 revenue à l'instantané **« T5 vierge »**, sans réseau ;
2. VirtualBox, Configuration > Dossiers partagés : dossier pointant sur la racine de la clé sur l'hôte, nom `cle`, montage automatique sur `Y:` (lecture seule conseillée) ;
3. dans la VM, PowerShell **en administrateur** (`\\VBoxSvr\cle` si `Y:` n'apparaît pas) :

   ```powershell
   robocopy Y:\ C:\OffPatch /E /XD "System Volume Information" '$RECYCLE.BIN'
   Set-Location C:\OffPatch
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan | Tee-Object -FilePath C:\OffPatch\T5-support-plan.txt
   ```

4. attendu : comme à la section 2 de `T5-T7-auto.md` (aucun `Blocking`, ESU en `Warning`, SSU et cumulative `Pending`, Defender `Pending`) ; aucun élément Windows 11 ni Office dans le plan, puisque le manifeste du support ne porte que win10-x64 ;
5. puis T5 en mode auto comme à la section 3 de `T5-T7-auto.md`, depuis `C:\OffPatch\Lancer-OffPatch.cmd` : Defender exécuté, aucune étape Windows, aucun redémarrage, rapport dans `C:\OffPatch\rapports\`.

## 4. À me renvoyer

- les deux captures de T8 ;
- `T5-support-plan.txt`, le contenu de la console du mode auto, le rapport HTML ;
- `C:\ProgramData\OffPatch\logs` de la VM.
