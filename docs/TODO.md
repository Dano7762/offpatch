# Backlog OffPatch

Une phase ne commence que lorsque la précédente est terminée, sauf indication contraire. Les tâches marquées [VM] sont des tests que David lance lui-même dans une machine virtuelle : Claude Code prépare la procédure et note le résultat qu'on lui communique.

## Phase 0 : recherche

Aucun code dans `app/`. Scripts d'essai dans `scratch/`.

- [x] R-01 Titres des cumulatives Windows dans le catalogue
- [ ] R-02 Cumulatives checkpoint
- [ ] R-03 Enablement package 26H2
- [ ] R-04 Windows 10 22H2 et ESU
- [ ] R-05 Cumulatives .NET Framework
- [ ] R-06 Définitions Defender
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
- [ ] Détection par catégorie (états `UpToDate`, `Pending`, `NotApplicable`, `MissingFromDepot`, `Error`)
- [ ] Planificateur : ordre, prérequis, points de redémarrage
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
