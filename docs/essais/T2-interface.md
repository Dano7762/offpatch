# Essai T2 depuis l'interface sur la VM Windows 11 (phase 6)

But : refaire la partie Windows de T2 (cahier des charges 12) en pilotant tout depuis l'interface WPF, qui remplace la console depuis le 22 octobre. On vérifie au passage ce que la console ne pouvait pas montrer : le récapitulatif du mode automatique, l'annulation d'un redémarrage, le bouton « Reprendre la session interrompue », la reprise seule après un redémarrage (`-Resume`) et la question posée à la fermeture de la fenêtre.

Pas de runner GitHub possible : il faut un Windows 11 x64 client et des redémarrages. T1 et la partie Office de T2 sont abandonnés (ta décision du 21 octobre) : si la VM n'a pas d'Office, la ligne Office est « Non applicable » et c'est normal.

## 0. Préparer la VM et l'hôte

1. **Veille de l'hôte désactivée** pour toute la durée de l'essai (Paramètres > Système > Alimentation, « Jamais »). OffPatch empêche la veille de la VM, pas celle de ton PC.
2. VM Windows 11 : il faut un Windows qui a des mises à jour à faire. Ta VM du 21 octobre est passée en 26H2 et n'a plus rien à installer. Restaure l'instantané **« T2 vierge »** (25H2, build 26200.8037) ; s'il n'existe plus, n'importe quel instantané 24H2 ou 25H2 antérieur au 19 octobre.
3. **Câble réseau virtuel débranché** (Configuration > Réseau > décocher « Câble branché »), avant de démarrer la VM.
4. Dossier partagé VirtualBox vers le dossier du projet sur l'hôte (`E:\Projets Claude\Mises à jour Windows et Office`), en lecture seule. Dans la suite, son nom dans la VM est `\\VBOXSVR\OffPatch` : remplace-le par le tien.

## 1. Copier l'outil sur C:\OffPatch

PowerShell **en administrateur** dans la VM (pas de clé USB : sa lecture dans la VM fausse les SHA-256) :

```powershell
$s = '\\VBOXSVR\OffPatch'
robocopy "$s\app" C:\OffPatch\app /MIR
robocopy "$s\config" C:\OffPatch\config /MIR
robocopy "$s\tools" C:\OffPatch\tools /E
robocopy "$s\depot" C:\OffPatch\depot /E /XD "$s\depot\office"
robocopy $s C:\OffPatch offpatch.root Lancer-OffPatch.cmd
```

`/XD` reçoit le chemin complet de `depot\office` : avec `/XD office` seul, robocopy écarterait aussi `config\office`. Si la VM a un Office Click-to-Run, supprime cette option : la source Office est alors nécessaire.

Contrôle : `Test-Path C:\OffPatch\app\gui\OffPatch.jpg` doit répondre `True` (sinon la copie date d'avant le logo).

## 2. Plan en lecture seule

Toujours dans PowerShell en administrateur :

```powershell
Set-Location C:\OffPatch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\OffPatch-Cli.ps1 -Action Plan | Tee-Object -FilePath C:\OffPatch\T2i-plan-1.txt
```

Attendu (25H2, 26200.8037, dépôt du 18 octobre) :

- contrôles préalables : aucun `Blocking` ; réseau `Ok` (hors ligne) ;
- Defender (plateforme, définitions) « Pending », sauf si l'instantané est plus récent que le dépôt ;
- checkpoint « UpToDate » ; cumulative `win11-x64-lcu-KB5127648` « Pending », `RebootAfter` vrai ;
- enablement package `win11-x64-ekb-26H2` « Pending », `RebootAfter` vrai ;
- .NET `KB5127690` « Pending » ou « UpToDate ».

**Si tu vois un `Blocking` ou une ligne `Error`, arrête-toi et envoie-moi `T2i-plan-1.txt`.**

## 3. L'interface et le récapitulatif

1. Double-clic sur `C:\OffPatch\Lancer-OffPatch.cmd`, accepter l'élévation. Une console reste ouverte derrière la fenêtre : c'est connu, ne la ferme pas (elle porte l'interface).
2. Vérifier : le logo et « version 0.1.0 » dans l'en-tête, la date du dépôt, le pied « © 2026 David Informaticien · Licence MIT · github.com/Dano7762/offpatch ». Onglet « Ce PC » : le même plan qu'à l'étape 2, les étapes à installer cochées, « Installation automatique » actif. Pas de bouton « Reprendre la session interrompue ».
3. Clic sur **« Installation automatique »**. Le récapitulatif s'ouvre. Attendu : la liste des étapes à installer, dans l'ordre, avec « — redémarrage ensuite » sur la cumulative et l'enablement package ; la ligne Office ; aucun bandeau jaune (PC hors ligne, sur secteur) ; pas de case « Forcer… » (elle n'apparaît que sous Windows 10 sans ESU). **Capture d'écran.**
4. Clic sur **« Annuler »**. Rien ne doit démarrer. Contrôle dans PowerShell : `Test-Path C:\ProgramData\OffPatch\state.json` doit répondre `False`.

## 4. Session automatique, avec un redémarrage annulé

1. **« Installation automatique »**, puis **« Démarrer l'installation automatique »**. Ensuite plus aucune question. Sous le tableau : « Étape … : en cours… », la barre qui défile, les lignes du journal.
2. Pendant une étape (Defender ou la cumulative), clic sur la **croix de la fenêtre**. Attendu : la question « Une session automatique est en cours. Fermer OffPatch quand même ? … ». Répondre **Non** : la fenêtre reste, la session continue.
3. Après la cumulative (jusqu'à 25 min), « Redémarrage dans 30 s » et le bouton **« Annuler le redémarrage »**. Clic dessus. Attendu : « Redémarrage annulé : état conservé. Redémarrer le PC, puis « Reprendre la session interrompue ». » ; après le relevé, le bandeau bleu « Un redémarrage est en attente » et le bouton « Reprendre la session interrompue » **grisé**, avec l'infobulle « Redémarrer d'abord le PC : la session reprendra ensuite. ». **Capture d'écran.**
4. Clic sur **« Redémarrer maintenant »**, confirmer. La VM redémarre. Comme le redémarrage a été annulé, la tâche de reprise a été retirée : rien ne se relance seul, c'est attendu.
5. Ouvrir la session, relancer `C:\OffPatch\Lancer-OffPatch.cmd`. Attendu : la cumulative « À jour », « Reprendre la session interrompue » **actif**. Clic dessus : pas de récapitulatif, la session reprend avec l'enablement package.
6. Compte à rebours après l'enablement package : **ne rien toucher**. Redémarrage, ouverture de session : l'interface doit **s'ouvrir seule** (tâche `OffPatch-Reprise`, puis `-Resume`) et continuer sans aucune question avec le .NET 26H2 (`KB5127694`) si nécessaire, puis le rapport. Fin : « Session automatique terminée. » et une ligne « Rapport : C:\OffPatch\rapports\….html ».

Si une étape est abandonnée après deux échecs, la session va quand même jusqu'au rapport : ne relance rien, garde la VM en l'état et envoie-moi ce qui est listé à la section 6.

## 5. Contrôles après la session

- Rapport `C:\OffPatch\rapports\AAAA-MM-JJ_<NomPC>_<Série>.html` : aucune étape en erreur, Windows avant (26200.8037) et après (26300.9711).
- `C:\ProgramData\OffPatch\` : plus de `state.json`, de `resume.ps1` ni de `temp\`.
- `Get-ScheduledTask -TaskName OffPatch-Reprise` : erreur « aucune tâche » (attendu).
- `winver` : 26H2, build 26300.9711.
- Relancer l'interface : rien à installer, pas de « Reprendre la session interrompue », « Installation automatique » grisé.

## 6. À me renvoyer

- `C:\OffPatch\T2i-plan-1.txt` ;
- les deux captures (récapitulatif ; état après « Annuler le redémarrage ») et, si quelque chose t'a surpris, une capture de plus ;
- le rapport HTML de `C:\OffPatch\rapports\` ;
- le dossier `C:\ProgramData\OffPatch\logs` (journaux de session et de reprise, archive `state_*.json`, journaux DISM).

Rien de secret là-dedans : le numéro de série d'une VM VirtualBox est fictif.
