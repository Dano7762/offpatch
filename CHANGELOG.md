# Journal des versions

Les dates sont celles de la publication sur GitHub. Le détail session par session est dans [docs/TODO.md](docs/TODO.md), la référence fonctionnelle dans le [cahier des charges](docs/CAHIER-DES-CHARGES.md).

## 1.0.0 (25 octobre 2026)

Première version stable.

### Ajouté depuis la bêta

- Assistant « Préparer un support… » dans l'onglet Dépôt, et action `Support` de la ligne de commande. On choisit le lecteur, les versions de Windows et les sources Office à embarquer. L'assistant refuse un lecteur en FAT32 (la cumulative Windows 11 x64 dépasse 4 Go), un lecteur trop petit, le lecteur de l'outil, ou un lecteur qui porte des dossiers `app`, `config`, `tools` ou `depot` étrangers à OffPatch.
- Copie de l'outil et du dépôt filtré, dossier par dossier, avec un manifeste réduit à ce que porte la clé. Les dossiers du dépôt qui ne servent plus sont retirés de la clé, son dossier `rapports\` n'est jamais touché.
- Rapatriement sur le PC du dépôt des rapports d'intervention restés sur la clé, avant la copie.
- Vérification de la clé après la copie : tailles, puis SHA-256 de chaque fichier du dépôt. En cas d'écart, le bilan dit de ne pas utiliser la clé en l'état.

### Modifié

- Point de restauration avant la première étape : désactivé par défaut (`client.createRestorePointBeforeSession` à `false`). Seul le cas « protection du système inactive » a pu être vérifié sur des PC réels. L'option se réactive dans `config\settings.json`.
- README refait : mise en place, routine mensuelle, déroulé sur le PC client, dépannage.

### Corrigé

- Avec `-WhatIf` sur un outil neuf, le dossier `logs` n'était pas créé et chaque ligne du journal affichait « Journal inaccessible ». Le journal s'ouvre maintenant aussi en essai à blanc.

### Validé

- T2 (partie Windows), T3, T5, T7 et T8 conformes, sur machines virtuelles, sur clé réelle et sur runners GitHub.
- Restent à voir sur de vrais PC clients, après la 1.0.0 : T1 (Windows 11 26H2 installé depuis une ISO), T4 (Windows 10 inscrit à l'ESU), T6 (Windows 11 ARM64 avec Office), et la mise à jour d'un Office Click-to-Run installé (partie Office de T2).

## 0.6.0-beta.1 (22 octobre 2026)

Première pré-version publique.

- Dépôt : cumulatives Windows 11 (24H2, 25H2, 26H2, x64 et ARM64) et Windows 10 22H2 (ESU) avec leurs prérequis, enablement package 26H2, cumulatives .NET Framework, plateforme et définitions Defender, sources Office par canal (Current, LTSC 2024, LTSC 2021) par l'Office Deployment Tool. Interrogation directe du Microsoft Update Catalog, contrôle de la signature et du SHA-256, dépôt sans doublons, purge selon la rétention.
- PC client : relevé du système, contrôles préalables, plan avec les redémarrages, installation manuelle ou automatique, reprise seule après chaque redémarrage (même si la clé change de lettre), rapport d'intervention HTML.
- Interface WPF (onglets Ce PC, Dépôt, Journal) et ligne de commande `app\OffPatch-Cli.ps1`.
