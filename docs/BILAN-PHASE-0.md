# Bilan de la phase 0

Établi le 6 octobre 2026. Ce document fait le point sur la recherche (`RECHERCHE.md`) avant la phase 1 et liste ce qui reste à décider. Le cahier des charges n'est modifié qu'après l'accord de David : seule la matrice de traçabilité, déjà acceptée le 4 octobre 2026, y a été ajoutée (version 1.19, section 12).

## 1. État des points de recherche

| Point | État | Condition de déblocage |
|---|---|---|
| R-01, R-03, R-05 à R-15 | Tranchés | — |
| R-02 Cumulatives checkpoint | Ouvert, non bloquant pour la phase 1 | Relancer `r02-arm64.yml` avec la cumulative d'octobre, après le Patch Tuesday du 13 octobre 2026 (installation réelle, sans préversion) |
| R-04 Windows 10 22H2 et ESU | Ouvert, non bloquant pour la phase 1 | Relevé en lecture seule `docs/essais/R-04-esu.md` sur un vrai PC Windows 10 22H2 |

Les points qu'aucun runner ne peut vérifier sont listés en tête de `RECHERCHE.md` (« À valider sur intervention réelle »).

## 2. Configuration complétée

- `config/settings.json` : valeurs du cahier des charges 1.18 (rétention par cible, `minFreeSpaceGB` 17, racines de confiance, 8 hôtes exacts).
- `config/pinned-items.json` : enablement package KB5121794 x64 et ARM64, SSU KB5031539 (R-03, R-04).
- `config/catalog-queries.json` (nouveau) : recherches et motifs établis en R-01, R-05 et R-06, pour les trois cibles et les catégories `windows-lcu`, `dotnet`, `defender-platform`. Contrôlé le 6 octobre 2026 sur le catalogue réel (`scratch/bilan-check-queries.ps1`, recherches d'août et septembre 2026) : KB5129195 retenu pour Windows 11 x64 et ARM64, KB5129236 et KB5122878 candidats pour Windows 10, KB5126052 pour .NET Windows 11, KB5126146 pour .NET Windows 10, plateforme Defender 4.18.26080.4 seule.
- `config/office/profiles.json` (nouveau) : les huit profils du tableau 3.3, avec `supportedOn` et sa source Microsoft.
- `tests/Unit/Config.Tests.ps1` (nouveau) : cohérence des fichiers entre eux (cibles couvertes, rétention par cible, motifs valides, dépendances vers des catégories connues, sources Office déclarées, clé de produit réservée aux licences en volume).

Le format de `catalog-queries.json` va plus loin que l'exemple du cahier des charges (6.2) : voir la proposition A ci-dessous.

## 3. Cases « à traiter » de la matrice et propositions

À décider par David avant la phase 1.

- **A. Format de `catalog-queries.json` (6.2).** Proposé, et déjà utilisé dans le fichier :
  - `searches` (liste) au lieu de `search` : une requête par version, puisque le catalogue s'arrête à 25 lignes par page ; la pagination (R-11) couvre le reste ;
  - `{month}` remplacé par le mois `AAAA-MM`, pour le mois courant et le précédent (`monthsToSearch` : 2, R-01) ;
  - `pick` : `highestUbr` (Windows 11, UBR le plus élevé dans le titre, R-01), `highestUbrFromReleaseInformation` (Windows 10, R-01), `latest` (.NET, R-05), `highestVersion` (plateforme Defender, version du titre) ;
  - `fileNamePattern` : choix du fichier d'une entrée qui en contient plusieurs (plateforme Defender : un exécutable par architecture).

  La règle de sélection « UBR le plus élevé » est à reporter en 6.2, comme prévu par R-01.
- **B. Emplacement des liens hors catalogue.** Les liens de mpam-fe.exe (`go.microsoft.com/fwlink/?LinkID=121721&arch=…`) et de la page de l'ODT (`www.microsoft.com/en-us/download/details.aspx?id=49117`) ne sont aujourd'hui écrits que dans le test en ligne. Proposition : une section `downloadPages` dans `settings.json`, avec un lien par usage (`defenderDefinitions.x64`, `defenderDefinitions.arm64`, `officeDeploymentToolPage`) ; à inscrire en 6.1.
- **C. Cas de planification manquants (12).** Proposés :
  - P7 : Defender désactivé (antivirus tiers) → plateforme et définitions `NotApplicable` avec motif, jamais en erreur ;
  - P8 : Windows 10 avec .NET 4.8 (`Release` entre 528040 et 533319) → fichier ndp48 de l'élément .NET ; avec 4.8.1 → ndp481 ;
  - P9 : Office existant bilingue fr-fr + en-us et source `current` en fr-fr seul → Office `NotApplicable`, « langue absente de la source », ODT non lancé.
- **D. Corrections du cahier des charges devenues inexactes.**
  - 8.3 : « Méthodes de détection, à confirmer en R-09 » → R-09 est tranché.
  - 6.3 : « La compatibilité de `<Remove>` combiné à `<Add>` … est à vérifier (R-08) » → validée en R-08.
  - 12 : mocks de « `Start-Process` » → `Invoke-OpProcess` (R-14) ; « dépôt privé » → dépôt public ; ajouter `catalog-contract.yml` (hebdomadaire) à la description des runners.
  - 8.3, fin : « Si la phase 0 montre que certaines étapes peuvent s'enchaîner avant un seul redémarrage (R-02, R-03), le planificateur regroupe les redémarrages » → la phase 0 ne l'a pas montré pour l'enablement package (R-03, règle maintenue, essai sur intervention réelle) ; checkpoint et cumulative s'enchaînent déjà dans la même étape.

## 4. Option « point de restauration avant session »

Note de David du 6 octobre 2026, examinée sans être inscrite au cahier des charges.

- Documentation (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1, consultée le 6 octobre 2026) : `Checkpoint-Computer` crée un point de restauration système ; points et cmdlets réservés aux systèmes clients (Windows 10, Windows 11) ; depuis Windows 8, pas plus d'un point par 24 heures, sinon l'erreur « A new system restore point cannot be created because one has already been created within the past 24 hours ». `Enable-ComputerRestore` active la protection du système (qui doit l'être d'abord sur le lecteur système).
- Contraintes pour OffPatch :
  - la protection du système peut être désactivée sur le PC ; l'activer laisserait une modification durable, contraire au critère de R-15 : OffPatch ne l'active pas ;
  - limite d'un point par 24 heures : sur un PC où un point existe déjà depuis moins de 24 heures (par exemple créé par Windows Update), la création échoue ;
  - la création prend du temps et de la place sur C: (non mesuré).
- Proposition, pour décision au moment de la phase 4 ou 5 : option `createRestorePointBeforeSession`, désactivée par défaut ; si activée et que la protection du système est active sur C:, création d'un point avant la première étape ; si elle est désactivée, ou si un point de moins de 24 heures existe, avertissement dans le journal et le rapport (avec la date du point existant), sans bloquer la session. Mesure de la durée et de l'espace consommé à faire sur runner `windows-11-arm` avant d'inscrire l'option.

## 5. Suite

Après les décisions A à D : cahier des charges mis à jour en une version, puis début de la phase 1 (socle : arborescence, module, chemins, journal, `Invoke-OpProcess`, lecture et validation de la configuration).
