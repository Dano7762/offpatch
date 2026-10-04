# Backlog OffPatch

Une phase ne commence que lorsque la précédente est terminée, sauf indication contraire. Les tâches marquées [VM] sont des tests réels. Claude Code les lance sur des runners GitHub hébergés quand c'est possible (workflows en déclenchement manuel, lus avec `gh`). Ce que les runners ne permettent pas (redémarrage, Windows 11 x64 client, Windows 10 ESU) est validé par David sur intervention réelle, en commençant par l'action `Plan` en lecture seule.

## Phase 0 : recherche

Aucun code dans `app/`. Scripts d'essai dans `scratch/`.

- [x] R-01 Titres des cumulatives Windows dans le catalogue
- [ ] R-02 Cumulatives checkpoint
- [x] R-03 Enablement package 26H2
- [ ] R-04 Windows 10 22H2 et ESU
- [x] R-05 Cumulatives .NET Framework
- [x] R-06 Définitions Defender
- [ ] R-07 ODT et sources Office
- [ ] R-08 Office déjà présent
- [ ] R-09 Détection des cumulatives installées
- [ ] R-10 Contrôle d'intégrité
- [ ] R-11 MSCatalogLTS
- [ ] R-12 Volumes
- [ ] R-13 Domaines de téléchargement
- [ ] R-14 Moteur d'installation des paquets
- [ ] R-15 Suspendre Windows Update pendant une session
- [ ] Bilan de phase : reporter dans le cahier des charges ce qui change (avec mon accord) et compléter `config/` avec les valeurs établies

## Phase 1 : socle

- [ ] Arborescence, `.gitignore`, `offpatch.root`, `PSScriptAnalyzerSettings.psd1`
- [ ] Module `OffPatch` : manifeste `.psd1`, chargement automatique de `Public/` et `Private/`
- [ ] `Get-OpRoot` et fonctions de chemins (racine, dépôt, ProgramData)
- [ ] `Write-OpLog` : niveaux, fichier de session, file de messages pour l'interface
- [ ] Lecture et validation de `settings.json`, `catalog-queries.json`, `profiles.json`
- [ ] Lecture, validation et écriture atomique du manifeste
- [ ] `Lancer-OffPatch.cmd` : élévation, contournement de la stratégie d'exécution, `Unblock-File`
- [ ] `OffPatch-Cli.ps1` : squelette avec le paramètre `-Action`
- [ ] Tests Pester du socle

## Phase 2 : dépôt Windows, .NET et Defender

- [ ] MSCatalogLTS embarqué dans `lib/` (version figée, licence)
- [ ] Recherche dans le catalogue et sélection selon `catalog-queries.json`
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
- [ ] Tests de planification `tests/Unit/Planner/` (fixtures d'état PC + manifeste, plan attendu dans l'ordre) : P1 24H2 .1742, P2 25H2 .9457 avec cumulative d'octobre au dépôt, P3 25H2 .9550, P4 26H2 à jour, P5 Windows 10 sans SSU récents
- [ ] Exécuteur Defender
- [ ] Exécuteur DISM avec gestion des codes retour
- [ ] Exécuteur Office : XML temporaire, clé en mémoire, suppression après usage
- [ ] Suspension et rétablissement de Windows Update
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
- [ ] Fin de session propre (tâche, fichiers temporaires, Windows Update, rapport)
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
