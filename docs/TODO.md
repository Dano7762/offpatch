# Backlog OffPatch

Une phase ne commence que lorsque la précédente est terminée, sauf indication contraire. Les tâches marquées [VM] sont des tests réels. Claude Code les lance sur des runners GitHub hébergés quand c'est possible (workflows en déclenchement manuel, lus avec `gh`). Ce que les runners ne permettent pas (redémarrage, Windows 11 x64 client, Windows 10 ESU) est validé par David sur intervention réelle, en commençant par l'action `Plan` en lecture seule.

## Phase 0 : recherche

Aucun code dans `app/`. Scripts d'essai dans `scratch/`.

- [x] R-01 Titres des cumulatives Windows dans le catalogue
- [ ] R-02 Cumulatives checkpoint : ouvert, non bloquant pour la phase 1 ; déblocage : `r02-arm64` avec la cumulative d'octobre, après le Patch Tuesday du 13 octobre 2026
- [x] R-03 Enablement package 26H2
- [ ] R-04 Windows 10 22H2 et ESU : ouvert, non bloquant pour la phase 1 ; déblocage : relevé `docs/essais/R-04-esu.md` sur un vrai PC Windows 10 22H2
- [x] R-05 Cumulatives .NET Framework
- [x] R-06 Définitions Defender
- [x] R-07 ODT et sources Office
- [x] R-08 Office déjà présent
- [x] R-09 Détection des cumulatives installées
- [x] R-10 Contrôle d'intégrité
- [x] R-11 MSCatalogLTS
- [x] R-12 Volumes
- [x] R-13 Domaines de téléchargement
- [x] R-14 Moteur d'installation des paquets
- [x] R-15 Suspendre Windows Update pendant une session
- [x] Bilan de phase : reporter dans le cahier des charges ce qui change (avec mon accord) et compléter `config/` avec les valeurs établies
  - [x] Ajouter au cahier des charges une matrice de traçabilité (accord de David du 2026-10-04), une ligne par catégorie (`windows-lcu`, `windows-checkpoint`, `windows-ekb`, `windows-ssu`, `dotnet`, `defender-platform`, `defender`, `office-source`). Colonnes : cibles concernées, source (requête catalogue ou élément épinglé), règle de détection, dépendances (`prerequisites` / `runsAfter`), position dans le plan, scénarios de test qui la couvrent (P1 à P5, T1 à T8, workflows). Toute case vide est un point à traiter avant la phase 1.
  - [x] Examiner l'option « point de restauration avant session » (note de David du 2026-10-06, pas encore au cahier des charges) : `Checkpoint-Computer` avant la première étape ; contraintes : protection du système désactivée sur certains PC (pas de point possible sans l'activer), un seul point par 24 h par défaut (`SystemRestorePointCreationFrequency`), espace réservé sur C:.

## Phase 1 : socle

- [x] Arborescence, `.gitignore`, `offpatch.root`, `PSScriptAnalyzerSettings.psd1`
- [x] Module `OffPatch` : manifeste `.psd1`, chargement automatique de `Public/` et `Private/`
- [x] `Get-OpRoot` et fonctions de chemins (racine, dépôt, ProgramData)
- [x] `Write-OpLog` : niveaux, fichier de session, file de messages pour l'interface
- [x] `Invoke-OpProcess` : fonction unique de lancement de processus sur `System.Diagnostics.Process` (jamais `Start-Process`, dont l'`ExitCode` revient vide sous PowerShell 5.1, R-14), utilisée par tous les exécuteurs (DISM, ODT, mpam-fe.exe, plateforme Defender) : code de sortie, sortie standard capturée, délai maximal facultatif ; tests Pester avec `cmd /c exit 0`, `exit 3010`, `exit 1618`, un délai dépassé et une sortie standard capturée
- [x] Lecture et validation de `settings.json`, `catalog-queries.json`, `profiles.json`
- [ ] Lecture, validation et écriture atomique du manifeste
- [ ] `Lancer-OffPatch.cmd` : élévation, contournement de la stratégie d'exécution, `Unblock-File`
- [ ] `OffPatch-Cli.ps1` : squelette avec le paramètre `-Action`
- [ ] Tests Pester du socle

## Phase 2 : dépôt Windows, .NET et Defender

- [ ] Recherche dans le catalogue et sélection selon `catalog-queries.json` (`Find-OpCatalogUpdate` et les fonctions d'analyse de R-11, déjà écrites et testées sur fixtures)
- [ ] Mode `-ListOnly`
- [ ] Téléchargement BITS avec reprise, repli `HttpClient`, dossier `.tmp`
- [ ] Vérification d'intégrité et calcul du SHA-256
- [ ] Définitions Defender x64 et ARM64
- [ ] Mise à jour du manifeste et résumé des nouveautés
- [ ] Purge selon la rétention, liste des orphelins
- [ ] Tests avec mocks réseau

## Phase 3 : dépôt Office

- [ ] Récupération et mise à jour de l'ODT dans `tools/odt/`
- [ ] Génération des XML de téléchargement par source et langues
- [ ] `/download` par source, relevé de la version obtenue
- [ ] Éléments `office-source` dans le manifeste, purge des anciennes versions
- [ ] Tests

## Phase 4 : installation en mode manuel (sans interface)

- [ ] `Get-OpSystemInfo` : système, version, build et UBR, architecture, édition, ESU, Office, espace libre, alimentation, fabricant, modèle, numéro de série
- [ ] Contrôles préalables (tableau 8.2)
- [ ] Détection par catégorie (états `UpToDate`, `Pending`, `NotApplicable`, `MissingFromDepot`, `SkippedPrerequisite`, `Error`)
- [ ] Planificateur : ordre, prérequis, points de redémarrage
- [ ] Tests de planification `tests/Unit/Planner/` (fixtures d'état PC + manifeste, plan attendu dans l'ordre) : P1 24H2 .1742, P2 25H2 .9457 avec cumulative d'octobre au dépôt, P3 25H2 .9550, P4 26H2 à jour, P5 Windows 10 sans SSU récents, P6 25H2 .9457 sans cumulative atteignant `minUbr` (enablement package « Ignorée (prérequis) »), P7 Defender désactivé, P8 .NET 4.8 / 4.8.1 sous Windows 10, P9 Office bilingue et source fr-fr, P10 Office sur un canal absent du dépôt
- [ ] Exécuteur Defender
- [ ] Exécuteur DISM avec gestion des codes retour
- [ ] Exécuteur Office : XML temporaire, clé en mémoire, suppression après usage
- [ ] Rapport d'intervention HTML
- [ ] Actions CLI : `Plan`, `InstallStep`, `Report`
- [ ] Tests avec mocks
- [ ] [VM] T3 puis T1 en pilotant étape par étape depuis la CLI

## Phase 5 : mode automatique

- [ ] `state.json` : création, mise à jour atomique, archivage
- [ ] `resume.ps1` : recherche du support (marqueur et numéro de série du volume), relance avec `-Resume`
- [ ] Tâche planifiée `OffPatch-Reprise` : création et suppression
- [ ] Compte à rebours, redémarrage, limite de redémarrages, double échec d'une étape
- [ ] Fenêtre d'attente quand le support est absent
- [ ] Fin de session propre (tâche, fichiers temporaires, rappel du mode Avion si le PC est hors ligne, rapport)
- [ ] Tests avec mocks
- [ ] [VM] T1, T2, T7

## Phase 6 : interface WPF

- [ ] `MainWindow.xaml` et chargement par `XamlReader`
- [ ] Infrastructure runspace, file de messages, `Dispatcher`, annulation
- [ ] En-tête (version, date du dépôt, alerte de fraîcheur)
- [ ] Onglet « Ce PC »
- [ ] Onglet « Dépôt »
- [ ] Onglet « Journal »
- [ ] Écran récapitulatif avant le mode automatique
- [ ] Reprise via `-Resume`
- [ ] [VM] T1 et T2 refaits depuis l'interface

## Phase 7 : support et rapports

- [ ] Assistant « Préparer un support » : filtre, contrôle du système de fichiers, espace libre
- [ ] Rapatriement des rapports déjà présents sur le support
- [ ] Copie robocopy dossier par dossier, manifeste filtré
- [ ] Vérification après copie
- [ ] [VM] T8, puis T4, T5 et T6 sur un support préparé

## Phase 8 : finitions

- [ ] Matrice T1 à T8 complète et à jour
- [ ] README : mise en place, routine mensuelle, dépannage
- [ ] CHANGELOG et numéro de version 1.0.0
- [ ] Revue finale PSScriptAnalyzer et nettoyage

## Journal des sessions

Une ligne par session, la plus récente en bas.

| Date | Phase | Fait | Reste ou blocage |
|---|---|---|---|
| 2026-10-04 | Préparation | Cahier des charges, CLAUDE.md, backlog et liste des points à vérifier | Démarrer la phase 0 |
| 2026-10-04 | 0 | R-01 tranché : forme des titres Windows 11 et 10, même KB publié sous 24H2/25H2/26H2 avec les mêmes fichiers, sélection par UBR max (OOB possibles), exclusion de 26H1, une requête par version (plafond de 25 résultats) | R-02 (KB5043080 livré avec chaque entrée de cumulative) |
| 2026-10-04 | 0 | Relecture R-01 : règles validées (UBR max, Windows 10 via release-information, mois courant + précédent), contrôle étendu dans scratch, cahier des charges 1.1 (`baseBuilds` + `resultingUbr`), décision de stockage par hash notée en R-02 | R-02 |
| 2026-10-04 | 0 | R-02 en cours : documentation dépouillée (méthodes 1 et 2, exploration du dossier par DISM), recommandation séquentielle depuis le dépôt avec un fichier par dossier, procédure VM rédigée (`docs/procedures-vm/R-02-checkpoint.md`), pistes notées en R-03, R-12, R-14 | Attente du test VM R-02 ; valider la structure du dépôt par hash ; PSScriptAnalyzer absent de la machine de développement |
| 2026-10-04 | 0 | Cahier des charges 1.2 (dépôt `files/<sha256>/`), CLAUDE.md : essais réels sur runners GitHub hébergés ; `.gitignore`, `PSScriptAnalyzerSettings.psd1`, `tests/runner/`, tests Pester de conventions, workflows `ci`, `r02-arm64`, `depot-x64` ; procédure R-02 réécrite (`docs/essais/`) | Pousser sur `Dano7762/offpatch`, lancer les workflows, puis R-03 |
| 2026-10-04 | 0 | Dépôt `Dano7762/offpatch` (privé) créé, CI au vert sous PowerShell 5.1. `depot-x64` : SHA-1 et Authenticode valides, 4,64 Go, domaine `catalog.sf.dl.delivery.mp.microsoft.com`. `r02-arm64` : runner déjà en 26200.9457, DISM renvoie 0 pour un paquet déjà installé, checkpoint visible en `RollupFix 26100.1742` à l'état Staged. R-03 bloqué : KB5121794 absent du catalogue (comme la 25H2), prérequis 26100.9546 non couvert par la cumulative de septembre | Décision de David sur R-03 (retrait de `windows-ekb` recommandé) ; relancer `r02-arm64` après le 13/10 ; suite : R-04 |
| 2026-10-04 | 0 | R-03 tranché : élément épinglé `config/pinned-items.json` (KB5121794 x64 et ARM64 vérifiés sur runner : SHA-1, Authenticode Microsoft, domaine), `minUbr` 9550 ; cahier des charges 1.3 (CurrentBuild, détection par UBR, éléments épinglés) ; `Get-OpWindowsIdentity` et tests ; passage croisé au catalogue : échec ARM64 non reproduit (15/15) | R-02 : relancer `r02-arm64` après le 13/10 ; suite : R-04 |
| 2026-10-04 | 0 | R-04 dépouillé : ESU entreprise détectable hors ligne (WMI `SoftwareLicensingProduct`, 3 identifiants d'activation documentés), ESU grand public sans méthode hors ligne documentée, paquet de préparation KB5126256 au catalogue, aucune doc sur le contrôle de licence à l'installation ; relevé en lecture seule `docs/essais/R-04-esu.md` | R-04 bloqué : relevé sur un vrai PC Windows 10 ; propositions (KB5126256 au dépôt, avertissement SSU) à trancher ; suite : R-05 |
| 2026-10-04 | 0 | Cahier des charges 1.4 (règles de prérequis du planificateur, `SkippedPrerequisite`, SSU Windows 10 en élément épinglé, tests P1 à P5, KB5126256 en évolution) ; KB5031539 vérifié sur runner et ajouté à `pinned-items.json` ; KB5005260 écarté (sans objet en 22H2) ; tâche de tests de planification ajoutée en phase 4 | R-05 en cours |
| 2026-10-04 | 0 | R-05 : titres et motifs .NET vérifiés (Windows 11 : même fichier pour 24H2/25H2/26H2 ; Windows 10 : entrée « 3.5, 4.8 and 4.8.1 » à deux fichiers, choix par la valeur `Release`) ; workflow `msu-inspect` : version du paquet lue dans le .msu identique à celle de la liste DISM | Accord de David sur la détection .NET par version de paquet (cahier des charges 8.3), puis R-06 |
| 2026-10-04 | 0 | R-05 tranché (détection .NET par version de paquet) ; cahier des charges 1.5 (7.1, 7.2 `package` et `netRelease`, 8.3, section 12 runners et interventions réelles avec matrice T1 à T8) ; R-09 : contre-vérification de `resultingUbr` par le .msu ; KB5005260 retiré (justification en R-04) ; CLAUDE.md : Pester et PSScriptAnalyzer en local avant chaque push | R-06 |
| 2026-10-04 | 0 | R-06 tranché : liens officiels mpam-fe.exe x64/ARM64 (version lisible dans l'URL de redirection), FileVersion = version des définitions, Authenticode valide ; antivirus tiers → Defender désactivé, non applicable ; workflow `r06-defender` : définitions du jour appliquées sur la plateforme de l'image sans mise à jour de plateforme, `-q` mesuré, code retour non probant | Plateforme très ancienne à valider sur intervention réelle ; suite : R-07 |
| 2026-10-04 | 0 | R-06 complété : temps réel actif sur le runner ARM64 (mesures valables), aucune garantie documentée pour une plateforme ancienne, KB4052623 testé sur runner (4.18.25080.5 → 4.18.26080.4 sans redémarrage) et proposé en prérequis des définitions ; cahier des charges 1.6 (détection Defender actif ou passif, non applicable jamais en erreur, rapport) | Décision de David sur KB4052623 ; suite : R-07 |
| 2026-10-04 | 0 | Cahier des charges 1.7 : plateforme Defender (KB4052623, Current Channel (Broad) seul) avant les définitions, deux types de dépendance (`prerequisites` bloquant, `runsAfter` d'ordre) dans le manifeste et `pinned-items.json`, attente bornée à 120 s ; essai complet sur runner ARM64 (définitions supprimées puis 1.459.384.0 → 1.459.553.0 après plateforme et mpam-fe.exe) | R-07 |
| 2026-10-04 | 0 | R-07 en cours : product IDs confirmés, canal `Current` pour les versions en boîte (même build que le Current Channel), Office 64 bits sur Arm confirmé (Windows 11 minimum), Office LTSC 2024 non pris en charge sur Windows 10 22H2, ODT récupérable par la page officielle (lien versionné) ; essai `r07-office.yml` préparé, non lancé | Accord de David pour télécharger une source Office sur runner (structure, `v64.cab`, anciennes versions) ; avertissement LTSC 2024 sur Windows 10 à trancher |
| 2026-10-04 | 0 | `graphify-out/` exclu du dépôt ; matrice de traçabilité par catégorie ajoutée au bilan de phase 0 (accord de David) | R-07 |
| 2026-10-04 | 0 | R-07 tranché : structure de la source et rôle de `v64.cab` mesurés (`r07-office`), règle de purge validée et installation hors ligne de Home2024Retail réussie sur ARM64 avec le CDN bloqué (`r07-install`, exécutables Office x64 émulés) ; cahier des charges 1.8 (3.3 sans « à vérifier », source Current unique, aucun profil pris en charge sur Windows 10 22H2 : avertissement en 8.2, 8.6, 8.8) | R-08 |
| 2026-10-04 | 0 | R-08 sur runner ARM64 (5 scénarios réussis) : `<Remove All>` + `<Add>` dans le même XML validé, mise à jour hors ligne par `/configure` (192 s) et par `OfficeC2RClient` + `UpdateUrl` temporaire (105 s), la source Current met à jour un O365HomePremRetail ; applications du Store intactes ; cahier des charges 1.9 (portée de `allowedDomains`) ; R-07 ARM64 « non concluant » | Langues (retrait, Office multilingue) à vérifier ; proposition pour le tableau 8.5 à trancher par David |
| 2026-10-05 | 0 | R-08 tranché : retrait de en-us confirmé par le registre Click-to-Run ; Office bilingue mis à jour depuis une source fr-fr seule → 17002 (avec ou sans `MatchInstalled`), client Click-to-Run mis à jour mais pas les applications, `VersionToReport` trompeur, Office utilisable ; source Current fr-fr 3 605 Mo, fr-fr + en-us 3 955 Mo ; cahier des charges 1.10 (langues par source, contrôle des langues avant l'ODT, tableau 8.5, `/configure` seul, retrait explicite) ; CLAUDE.md : édition par l'outil natif | R-09 (proposer la version de `WINWORD.EXE` comme contrôle de la détection Office) |
| 2026-10-05 | 0 | R-09 tranché : détection des cumulatives par build et UBR (DISM et `Get-HotFix` en diagnostic) ; .msu Windows 10 KB5129236 : `Package_for_RollupFix` 19041.7727.1.0 = UBR attendu, SSU du mois embarqué ; .msu Windows 11 illisible par `expand.exe`, l'UBR du titre fait foi | Décision de David sur la détection Office par la version de `WINWORD.EXE` ; suite : R-10 |
| 2026-10-05 | 0 | Cahier des charges 1.11 (version d'Office par `WINWORD.EXE`, tableau 8.5) et 1.12 (intégrité, garde-fou de 30 min sur l'ODT) ; README ; R-10 tranché sur runner ARM64 : tous les fichiers signés `Valid` vers Microsoft Root CA 2010 (plateforme Defender signée « Microsoft Windows Publisher »), SSU 2023 expiré mais horodaté valide, contrôle hors ligne sans blocage (62,8 s pour 4,4 Go), `.dat` Office non signés mais couverts par des `.dat.cat`, source corrompue : l'ODT attend le réseau sans échouer (> 20 min) | R-11 |
| 2026-10-05 | 0 | Cahier des charges 1.13 (racines de confiance par empreinte) ; R-11 : MSCatalogLTS 2.1.0.2 (MIT, actif) comparé à notre implémentation, 0 résultat avec la requête de R-01 (réécriture de la recherche), DLL non signée, 1 538 lignes contre 88 ; fonctions d'analyse `ConvertFrom-OpCatalogSearchPage` et `ConvertFrom-OpCatalogDownloadDialog`, fixtures de pages réelles, contrat en ligne dans la CI | Accord de David sur le retrait de MSCatalogLTS (cahier des charges 5 et 7.1, CLAUDE.md, backlog phase 2) |
| 2026-10-06 | 0 | R-11 clos : MSCatalogLTS retiré (cahier des charges, CLAUDE.md, backlog), pagination `&p=` dans `Find-OpCatalogUpdate` avec plafond, `catalog-contract.yml` hebdomadaire, `ci.yml` sans réseau ; `Test-OpFileSignature` et contrôle de racine dans `depot-x64` (racine Microsoft Root CA 2010 reconnue) ; `config/settings.json` créé ; R-12 tranché : dépôt complet 23 Gio, pic de mise à jour 43,9 Gio, support de 64 Go, pic de 10,7 Gio sur C: (ARM64, préversion KB5124010, trois runs), `minFreeSpaceGB` 17, rétention par cible proposée 1/1/2 ; cahier des charges 1.14 ; R-03 : KB5121794 accepté par DISM (3010) avant et après la cumulative sans redémarrage, en attente avec elle ; codes DISM reportés en R-14 ; analyse du magasin de composants bloquée avec redémarrage en attente, bornée à 10 min | Décision de David sur l'enchaînement de l'enablement package avant un redémarrage unique (à vérifier sur intervention réelle) ; suite : R-13 |
| 2026-10-06 | 0 | Décisions de David : rétention 1/1/2 et support de 64 Go validés ; enablement package toujours après le redémarrage de la cumulative, essai de regroupement inscrit « à valider sur intervention réelle » (point de restauration avant) ; cahier des charges 1.15 (`minUbr` contrôlé par OffPatch seul, cas P6) ; CLAUDE.md (pas de `gh run watch`, aucune maintenance du magasin de composants avec un redémarrage en attente, script R-02 aligné) ; option « point de restauration avant session » notée pour le bilan | R-13 |
| 2026-10-06 | 0 | R-13 mesuré (lecture seule, mêmes hôtes que sur les runners) : 8 noms d'hôte exacts, tous en `https`, seule redirection `go.microsoft.com` → `definitionupdates.microsoft.com` ; deux entrées de la liste 6.1 ne correspondent à aucun hôte réel | Accord de David sur la liste et la règle « nom d'hôte exact, contrôlé à chaque redirection » (cahier des charges 6.1, `settings.json`), puis R-14 |
| 2026-10-06 | 0 | R-13 tranché : 8 hôtes exacts dans `settings.json`, `Resolve-OpDownloadUrl` (redirections résolues une à une, http réécrit en https, refus avec la ligne à ajouter) et ses tests ; contrat hebdomadaire étendu aux liens réels du moment (18 liens conformes) ; cahier des charges 1.16 (6.1, 7.1, 11, limite de BITS) | R-14 |
| 2026-10-06 | 0 | R-14 : documentation Microsoft dépouillée (`/PackagePath` et dossiers, checkpoints, `/LogPath`, `/NoRestart`, `Add-WindowsPackage`, codes CBS documentés) ; essai `r14-dism.yml` préparé (cas limites, `dism.exe` comparé à `Add-WindowsPackage`) | Bloqué : GitHub refuse de démarrer les jobs (paiement ou plafond de dépenses du compte) ; contrat du catalogue du jour non exécuté pour la même raison |
| 2026-10-06 | 0 | Dépôt passé en public (licence MIT, README) ; `windows-11-arm` démarre sans refus ; contrat du catalogue réussi sur runner ; R-14 mesuré : un .msu non applicable renvoie 0 (0x800f081e seulement dans le journal DISM), 3010 pour l'enablement package, 0xCA00A009 pour un .msu altéré, 3 pour un chemin absent ; `dism.exe` préféré à `Add-WindowsPackage` ; README : désactivation des workflows planifiés après 60 jours | Accord de David sur la nouvelle règle de jugement d'une étape DISM (cahier des charges 8.4), puis R-15 |
| 2026-10-06 | 0 | R-14 tranché, cahier des charges 1.17 : `dism.exe` par chemin complet, jugement en deux temps (liste DISM puis UBR après redémarrage), `NotApplicable` par le journal avec avertissement, contrôle bloquant du PowerShell 32 bits | R-15 |
| 2026-10-06 | 0 | R-15 mesuré (`r15-windowsupdate`, ARM64) : arrêt simple de `wuauserv` relancé seul après 4 min 49 s, DISM indifférent à l'arrêt ; `IAutomaticUpdates::Pause` sans effet depuis Windows 10 ; pause par stratégie exclue (Famille non couverte, 35 jours) ; pause « Paramètres » sans méthode programmatique documentée | Accord de David sur la règle proposée (`pauseWindowsUpdateDuringSession` à `false`, arrêt simple avant chaque étape si activé, réseau coupé recommandé), puis bilan de phase 0 |
| 2026-10-06 | 0 | R-15 tranché, cahier des charges 1.18 : option de suspension retirée, mode Avion recommandé et rappel en fin de session ; essai de deux DISM simultanés (le second attend, pas d'erreur), nouvelle tentative après 5 min sur 1618 / 0x80070652 ; contrôle en ligne local en échec passager du catalogue, repassé ensuite | Bilan de phase 0 |
| 2026-10-06 | 0 | Politique de nouvelles tentatives (`Invoke-OpWebRequest`, `Invoke-OpHeadRequest`), `Get-OpCatalogDownloadLink`, contrat en ligne sur le code de production avec diagnostic et relance unique ; tests avant push hors `Live` ; `Invoke-OpProcess` au backlog ; bilan de phase 0 : R-02 et R-04 ouverts non bloquants, `catalog-queries.json` et `office/profiles.json` créés et contrôlés, tests de cohérence de `config/`, matrice de traçabilité (cahier des charges 1.19), `docs/BILAN-PHASE-0.md` | Décisions de David sur les points A à D du bilan, puis phase 1 |
| 2026-10-06 | 0 | Bilan de phase 0 clos, cahier des charges 1.20 : format de `catalog-queries.json` (`latestMonth` sur le préfixe `AAAA-MM`), `downloadPages` lu par le contrat en ligne, P7 à P10, corrections ; point de restauration mesuré (`restore-point.yml`) : `Checkpoint-Computer` active lui-même la protection, état lu avant l'appel (`SPP\Clients`, indicateur non documenté), avertissement sans erreur dans les 24 h | Phase 1 |
| 2026-10-06 | 1 | Arborescence de la section 5 (`Public/`, `gui/Dialogs/`, `tools/odt/`), `offpatch.root` (JSON : produit, identifiant d'installation), tests de structure et d'exclusions git | Module `OffPatch` : manifeste et chargement |
| 2026-10-06 | 1 | Module `OffPatch` : manifeste (PowerShell 5.1, Desktop, `FunctionsToExport` explicite), `OffPatch.psm1` (StrictMode, chargement de `Private/` puis `Public/`, export limité à `Public/`, erreur qui nomme le fichier fautif) ; tests sur une copie du module | `Get-OpRoot` et fonctions de chemins |
| 2026-10-06 | 1 | `Get-OpRoot` (remontée jusqu'à `offpatch.root`, aucune lettre de lecteur mémorisée) et `Get-OpPath` (emplacements du support et de ProgramData, sans création de dossier), tests sur arborescences simulées | `Write-OpLog` |
| 2026-10-06 | 1 | `Start-OpLog` (journal du dépôt ou de session, sous-dossier des journaux DISM et ODT) et `Write-OpLog` (format de la section 10, niveau minimal, file de messages pour l'interface, clé de produit masquée, jamais bloquant) | `Invoke-OpProcess` |
| 2026-10-06 | 1 | `Invoke-OpProcess` sur `System.Diagnostics.Process` : code de sortie, sorties lues en parallèle, délai maximal facultatif avec arrêt de l'arborescence (`taskkill /T /F` : un processus enfant gardait les sorties ouvertes), `-WhatIf` ; tests 0, 3010, 1618, délai dépassé, sorties capturées, sortie volumineuse | Lecture et validation de la configuration |
| 2026-10-06 | 1 | Point de restauration, cahier des charges 1.21 : second indicateur `Win32_ShadowStorage` (documenté), concordance exigée avec `SPP\Clients` ; relevé sur runner (désaccords réels : protection activée sans point, protection désactivée avec réservation restante), relecture après l'appel, critère d'acceptation en 13 | Lecture et validation de la configuration |
| 2026-10-06 | 1 | `Invoke-OpProcess` : délai obligatoire (`-TimeoutSeconds` ou `-NoTimeout` explicite), appel sans délai refusé ; essai `r08-keylog` lancé (fausse clé dans les journaux ODT) ; `Read-OpJsonFile`, `Test-OpConfiguration` (règles de 6.1 à 6.4, messages en français), `Get-OpConfiguration` (toutes les anomalies dans une seule erreur), 15 cas d'altération testés | Résultat de `r08-keylog`, puis manifeste |
| 2026-10-06 | 1 | Clé de produit (R-08, cahier des charges 1.22) : trois passages `r08-keylog` ; l'ODT accepte une fausse clé (code 0), écrit la clé en clair dans son journal principal UTF-16 du TEMP et ignore `<Logging Path>` ; masquage `ConvertTo-OpMaskedText` / `Protect-OpLogFile` (encodage d'origine, toutes formes de la clé), contrôle de forme `Test-OpProductKeyFormat` | Manifeste : lecture, validation, écriture atomique |
