# Essais T1 et T2 en mode automatique sur une VM Windows 11 x64 (phase 5)

Aucun runner GitHub ne convient : il faut un Windows 11 x64 client et des redémarrages. Les essais se font sur des VM VirtualBox chez toi, jetables grâce aux instantanés. Le mode automatique tourne encore en console (`Lancer-OffPatch.cmd` → `app\OffPatch.ps1`), l'interface WPF viendra en phase 6. On commence toujours par l'action `Plan`, en lecture seule.

- **T1** : Windows 11 26H2 x64 installé depuis une ISO, sans Office. Attendu (cahier des charges 12) : mode auto complet, Office « NotApplicable » (aucun Office Click-to-Run), rapport sans erreur.
- **T2** : Windows 11 24H2 x64 avec un Office Click-to-Run ancien (Microsoft 365 Famille ou Office 2024, canal Current). Attendu : enablement package appliqué, Office mis à jour depuis la source Current, licence inchangée.

Ta VM 26H2 ne démarre plus (écran noir, 18 octobre). Si elle reste inutilisable, commence par T2 : c'est le passage le plus riche (cumulative, enablement package, deux redémarrages, Office), et la VM T2 terminée est un 26H2 à jour qui sert aussi pour T3 (section 5).

## 1. Dépôt et support

Le dépôt du 18 octobre convient : cumulative `KB5127648` (26100.9711, builds 26100, 26200 et 26300), checkpoint `KB5043080` jointe, enablement package 26H2 `KB5121794`, .NET `KB5127690` (24H2, 25H2) et `KB5127694` (26H2), Defender 4.18.26090.9 et 1.461.84.0, source Office Current 16.0.20430.20182.

Support : une clé USB NTFS ou un second disque virtuel NTFS, avec à la racine une copie de l'outil depuis la dernière version du dépôt git : `app\`, `config\`, `tools\`, `depot\`, `offpatch.root`, `Lancer-OffPatch.cmd`. Dans la suite, `E:` désigne sa lettre dans la VM.

## 2. Préparer les VM

### VM T1

1. Windows 11 26H2 x64 depuis l'ISO, sans Office.
2. **Câble réseau virtuel débranché** avant la première ouverture de session si possible (sinon dès l'installation finie) : Windows Update ne doit pas travailler en parallèle.
3. Instantané **« T1 vierge »**, support branché.

### VM T2

1. Windows 11 24H2 x64 depuis une ISO 24H2 (build 26100).
2. Réseau **branché** le temps d'installer Office, dans une version **plus ancienne** que la source du dépôt (sinon Office est déjà à jour et l'essai ne prouve rien). Avec l'ODT (`setup.exe` de `tools\odt\` convient), un fichier `ancien.xml` :

   ```xml
   <Configuration>
     <Add OfficeClientEdition="64" Channel="Current" Version="16.0.xxxxx.xxxxx">
       <Product ID="O365HomePremRetail">
         <Language ID="fr-fr" />
       </Product>
     </Add>
     <Updates Enabled="FALSE" />
     <Display Level="Full" AcceptEULA="TRUE" />
   </Configuration>
   ```

   - `Product ID` : `O365HomePremRetail` pour Microsoft 365 Famille, `Home2024Retail` pour Office Famille 2024, selon la licence que tu as ;
   - `Version` : une build du canal Current d'il y a deux ou trois mois, prise dans la page Learn « Update history for Microsoft 365 Apps (listed by date) » ; je ne l'écris pas ici pour ne pas en inventer une.

   Puis `setup.exe /configure ancien.xml`, ouvrir Word et activer avec ton compte.
3. Relevé de la licence **avant** : Word > Fichier > Compte, capture d'écran ; et dans PowerShell :

   ```powershell
   Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration |
     Select-Object ProductReleaseIds, VersionToReport, CDNBaseUrl, Platform |
     Format-List | Out-File E:\T2-office-avant.txt
   ```

4. **Câble réseau virtuel débranché**, puis instantané **« T2 vierge »**, support branché.

## 3. Plan en lecture seule (chaque VM)

PowerShell **en administrateur** dans la VM :

```powershell
Set-Location E:\
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan | Tee-Object -FilePath E:\T1-plan-1.txt
```

(`T2-plan-1.txt` pour T2.)

Attendu pour T1 (build 26300) :

- contrôles préalables : aucun `Blocking`, réseau `Ok` (hors ligne) ;
- plateforme et définitions Defender « Pending » (sauf si l'ISO est plus récente que le dépôt) ;
- checkpoint « UpToDate » (UBR ≥ 1742) ; cumulative `win11-x64-lcu-KB5127648` « Pending », `RebootAfter` vrai ;
- enablement package « NotApplicable » (déjà en 26H2) ; .NET `KB5127694` « Pending » ou « UpToDate », `KB5127690` « NotApplicable » ;
- Office « NotApplicable », motif « Aucun Office Click-to-Run. ».

Attendu pour T2 (build 26100) :

- Defender comme T1 ; checkpoint « UpToDate » si l'ISO est en 26100.1742 ou plus, sinon « Pending » avant la cumulative ;
- cumulative « Pending », `RebootAfter` vrai ;
- enablement package `win11-x64-ekb-26H2` « SkippedPrerequisite » (UBR sous 9550 tant que la cumulative n'est pas passée) : c'est normal, le plan est recalculé après le redémarrage ;
- .NET `KB5127690` « Pending » ou « UpToDate » ;
- Office `office-current-16.0.20430.20182` « Pending », dernière étape.

**Envoie-moi le fichier du plan avant d'aller plus loin** si quelque chose diffère (surtout un `Blocking` ou une ligne `Error`).

## 4. Mode automatique

Double-clic sur `E:\Lancer-OffPatch.cmd`, accepter l'élévation. Le plan s'affiche, puis la confirmation « Démarrage de la session automatique » : répondre **O**. Ensuite, ne rien toucher : à chaque étape qui redémarre, compte à rebours de 30 s, redémarrage, ouverture de session (la tâche `OffPatch-Reprise` relance OffPatch tout seul, sans question), suite des étapes. À la fin : `Session automatique : Completed.`, chemin du rapport, « Appuyer sur Entrée pour fermer ». Copie le contenu de la dernière console dans `E:\T1-console.txt` (ou `T2-console.txt`).

Déroulé attendu pour T1 : Defender (plateforme puis définitions), cumulative, **redémarrage 1/5**, .NET si « Pending », rapport.

Déroulé attendu pour T2 : Defender, checkpoint si besoin, cumulative, **redémarrage 1/5** ; à la reprise, plan recalculé : enablement package « Pending » (UBR 9711), installé, **redémarrage 2/5** ; à la reprise, build 26300 : .NET `KB5127694` à la place de `KB5127690` si nécessaire, puis Office (`setup.exe /configure` depuis `E:\depot\office\current`, jusqu'à 30 min), rapport.

Si une étape est abandonnée après deux échecs, la session continue jusqu'au rapport : ne relance rien, garde l'état de la VM et envoie-moi la console et les journaux (section 6).

## 5. Contrôles après la session

Pour les deux VM :

- rapport `E:\rapports\AAAA-MM-JJ_<NomPC>_<Série>.html` : aucune étape en erreur, Windows avant et après (T1 : UBR 9711 ; T2 : build 26300.9711), versions Defender, redémarrages comptés (T1 : 1 ; T2 : 2), rappel hors ligne ;
- `C:\ProgramData\OffPatch\` : plus de `state.json`, de `resume.ps1` ni de `temp\` ; `logs\` contient le journal de session, l'archive `state_*.json`, `resume_*.log` et la copie du rapport ;
- `Get-ScheduledTask -TaskName OffPatch-Reprise` : erreur « aucune tâche » (attendu) ;
- `winver` : 26H2, build 26300.9711.

En plus pour T2 :

- Office dans le rapport : version après 16.0.20430.20182 ;
- licence **après** : même commande qu'à l'étape 2.3 vers `E:\T2-office-apres.txt`, et Word > Fichier > Compte (capture). Attendu : mêmes `ProductReleaseIds`, même `CDNBaseUrl`, `VersionToReport` 16.0.20430.20182, produit toujours activé, aucune demande de clé ni de connexion ;
- T3 dans la foulée : relancer `-Action Plan` vers `E:\T3-plan.txt`. Attendu : aucune ligne « Pending » ni « Error » (Windows 11 26H2 à jour, rien à installer). Si c'est le cas, la tâche [VM] T1/T3 de la phase 4 avance aussi.

## 6. À me renvoyer

- les fichiers `E:\T1-*.txt`, `E:\T2-*.txt`, `E:\T3-plan.txt` ;
- les rapports HTML (`E:\rapports\`) ;
- le dossier `C:\ProgramData\OffPatch\logs` de chaque VM (journaux de session, de reprise, DISM, ODT) ;
- pour T2, les deux captures de Word > Fichier > Compte.

Ni clé ni secret là-dedans : l'ODT n'en reçoit pas et OffPatch masque toute clé dans ses journaux. Le numéro de série d'une VM VirtualBox est fictif.
