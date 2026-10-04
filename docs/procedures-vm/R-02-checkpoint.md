# Procédure VM R-02 : cumulatives checkpoint

But : choisir entre l'installation séquentielle depuis le dépôt (méthode A) et le dossier unique (méthode B), compter les redémarrages, relever les codes retour de DISM, y compris quand la checkpoint est déjà installée (pour R-14), et la forme des paquets dans la liste DISM (pour la détection).

Paquets testés : KB5129195 (cumulative de septembre 2026, 26x00.9457) et sa checkpoint KB5043080 (26100.1742), en x64.

## 0. Préparation (sur ta machine, une seule fois)

1. Télécharger la paire de .msu (5,2 Go au total, autorisé pour ce test) :

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scratch\r02-download-pair.ps1 -Kb KB5129195 -Arch x64 -Destination D:\R02-msu
   ```

   Résultat attendu : deux fichiers, chacun avec la mention « SHA-1 conforme au nom de fichier ».
   - `windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu` : 533 761 740 octets
   - `windows11.0-kb5129195-x64_ed361878ec2b56a7dfdb8f256565263a7fdc8eaa.msu` : 4 639 422 594 octets

2. Préparer un disque de données pour la VM (VHDX formaté en NTFS, **pas FAT32** : la cumulative dépasse 4 Gio), avec cette arborescence. Elle imite le dépôt dédoublonné par hash, un fichier par dossier :

   ```
   R02\A\checkpoint\windows11.0-kb5043080-x64_….msu
   R02\A\lcu\windows11.0-kb5129195-x64_….msu
   R02\B\windows11.0-kb5043080-x64_….msu
   R02\B\windows11.0-kb5129195-x64_….msu
   ```

   Aucun autre fichier dans ces dossiers. La lettre du disque dans la VM est notée `X:` ci-dessous.

3. Supports d'installation :
   - Scénario (a), 24H2 sans KB5043080 : il faut un support de build **inférieure à 26100.1742**. La 24H2 est sortie le 2024-10-01 directement en 26100.1742, qui est la build de KB5043080 : une ISO 24H2 publique standard intègre donc déjà la checkpoint. Vérifier la build avant d'installer : `dism /Get-WimInfo /WimFile:<lecteur>:\sources\install.wim /Index:1`, ligne « Version ». Si tu n'as aucun support antérieur à 1742, faire quand même le scénario avec une ISO 24H2 standard : il mesurera le cas « checkpoint déjà présente ».
   - Scénario (b), 26H2 depuis l'ISO actuelle : la 26H2 est sortie le 2026-09-29 en 26300.9457, soit la build de KB5129195. Si l'ISO est à 9457, les deux paquets sont déjà présents et le scénario mesure les codes retour « déjà installé ». Une vraie installation sur 26H2 sera possible avec la cumulative d'octobre (13/10/2026).

4. Dans chaque VM : installation hors ligne (sans réseau, pour que Windows Update n'interfère pas), compte local, puis **point de contrôle Hyper-V `R02-propre`** juste après la première ouverture de session et le branchement du disque `X:`. Le réseau reste coupé pendant tous les essais.

## 1. Relevé initial (à faire avant chaque méthode)

PowerShell **en administrateur** :

```powershell
New-Item -ItemType Directory -Force C:\R02 | Out-Null
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"$($v.CurrentBuild).$($v.UBR) $($v.DisplayVersion)" | Tee-Object C:\R02\build-avant.txt
dism.exe /English /Online /Get-Packages /Format:Table > C:\R02\packages-avant.txt
Get-HotFix | Format-Table -AutoSize | Out-File C:\R02\hotfix-avant.txt
```

## 2. Méthode A : séquentielle, un fichier par dossier

Partir du point de contrôle `R02-propre`.

```powershell
# Étape 1 : checkpoint
dism.exe /English /Online /Add-Package /PackagePath:X:\R02\A\checkpoint\windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu /NoRestart /LogPath:C:\R02\A1-checkpoint.log
"A1 code retour : $LASTEXITCODE" | Tee-Object -Append C:\R02\resultats.txt
Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' | Tee-Object -Append C:\R02\resultats.txt

# Étape 2 : cumulative, SANS redémarrer entre les deux
dism.exe /English /Online /Add-Package /PackagePath:X:\R02\A\lcu\windows11.0-kb5129195-x64_ed361878ec2b56a7dfdb8f256565263a7fdc8eaa.msu /NoRestart /LogPath:C:\R02\A2-lcu.log
"A2 code retour : $LASTEXITCODE" | Tee-Object -Append C:\R02\resultats.txt
```

- Si l'étape 2 refuse de s'installer à cause d'un redémarrage en attente : noter le code et le message, redémarrer, relancer l'étape 2, et compter ce redémarrage.
- Redémarrer, puis relancer la commande de build du point 1. Redémarrer encore si Windows le demande, et noter le nombre total de redémarrages.

Résultat attendu : build finale `<base>.9457` (26100.9457 en 24H2, 26300.9457 en 26H2).

Ensuite, **sans revenir au point de contrôle**, mesurer le cas « déjà installé » :

```powershell
dism.exe /English /Online /Add-Package /PackagePath:X:\R02\A\checkpoint\windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu /NoRestart /LogPath:C:\R02\A3-checkpoint-deja.log
"A3 checkpoint déjà installée, code retour : $LASTEXITCODE" | Tee-Object -Append C:\R02\resultats.txt
dism.exe /English /Online /Add-Package /PackagePath:X:\R02\A\lcu\windows11.0-kb5129195-x64_ed361878ec2b56a7dfdb8f256565263a7fdc8eaa.msu /NoRestart /LogPath:C:\R02\A4-lcu-deja.log
"A4 cumulative déjà installée, code retour : $LASTEXITCODE" | Tee-Object -Append C:\R02\resultats.txt
dism.exe /English /Online /Get-Packages /Format:Table > C:\R02\packages-apres-A.txt
Get-HotFix | Format-Table -AutoSize | Out-File C:\R02\hotfix-apres-A.txt
```

Puis, uniquement pour le scénario (a), essai complémentaire : revenir au point de contrôle `R02-propre` et lancer **directement l'étape 2** (cumulative seule, checkpoint absente et pas dans le dossier). Noter le code retour (`A5`). Cela montre ce qui se passe si un prérequis manque.

## 3. Méthode B : dossier unique

Revenir au point de contrôle `R02-propre`, refaire le relevé du point 1.

```powershell
dism.exe /English /Online /Add-Package /PackagePath:X:\R02\B\windows11.0-kb5129195-x64_ed361878ec2b56a7dfdb8f256565263a7fdc8eaa.msu /NoRestart /LogPath:C:\R02\B1.log
"B1 code retour : $LASTEXITCODE" | Tee-Object -Append C:\R02\resultats.txt
```

Redémarrer, relever la build, compter les redémarrages comme pour la méthode A. Noter aussi la durée de la commande, approximativement.

## 4. Ce qu'il faut me renvoyer

Le dossier `C:\R02` de chaque VM (journaux DISM compris), ou à défaut ce tableau rempli :

| Scénario | Build de départ | Méthode | Codes retour | Redémarrages nécessaires | Build finale |
|---|---|---|---|---|---|
| (a) 24H2 | | A (A1, A2) | | | |
| (a) 24H2 | | A5 (cumulative seule) | | — | |
| (a) 24H2 | | B (B1) | | | |
| (b) 26H2 | | A (A1, A2) | | | |
| (b) 26H2 | | B (B1) | | | |
| (a) et (b) | | Déjà installé (A3, A4) | | — | |

Et les lignes de `packages-apres-A.txt` qui concernent les cumulatives (nom du paquet `Package_for_RollupFix…` ou autre, état, date), plus le contenu de `hotfix-apres-A.txt`.
