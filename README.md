# OffPatch

Outil Windows portable qui prépare une fois par mois un dépôt de mises à jour Microsoft, puis les installe **sans connexion Internet** sur des PC traités un par un : en atelier, ou chez un client. Il prend la suite de WSUS Offline Update, qui n'est plus maintenu.

> **État du projet : phase 0 (recherche).** Aucune version utilisable n'est encore publiée. Les choix techniques sont établis et vérifiés un par un, sources et essais à l'appui, avant d'écrire le code de l'outil.

## Ce que fait OffPatch

**Côté dépôt** (PC connecté, une fois par mois) : il télécharge et vérifie

- les cumulatives Windows 11 (24H2, 25H2, 26H2, x64 et ARM64) et Windows 10 22H2 (x64, ESU), avec leurs prérequis (cumulatives « checkpoint », SSU) ;
- l'enablement package Windows 11 26H2 ;
- les cumulatives .NET Framework ;
- la plateforme et les définitions Microsoft Defender ;
- les sources d'installation Office (versions en boîte 2021 et 2024, Office LTSC 2021 et 2024), par l'Office Deployment Tool.

Chaque fichier est contrôlé au téléchargement (signature Authenticode Microsoft, SHA-256) et rangé dans un dépôt dédoublonné, décrit par un manifeste.

**Côté client** (PC hors ligne, depuis une clé USB ou un disque) : il détecte ce qui manque, établit un plan avec les redémarrages nécessaires, revérifie l'intégrité des fichiers juste avant de s'en servir, installe, puis écrit un rapport d'intervention HTML. Un mode automatique enchaîne les étapes et reprend après chaque redémarrage.

## Principes

- Windows PowerShell 5.1 seulement, rien à installer sur le PC client, x64 et ARM64.
- Téléchargements uniquement depuis des domaines Microsoft autorisés.
- Aucune activation en dehors des mécanismes Microsoft officiels ; aucune clé de produit écrite sur disque ni dans un journal.
- Les données qui changent avec Microsoft (titres du catalogue, product IDs, liens) vivent dans la configuration, pas dans le code.

## Installation depuis GitHub

Si vous téléchargez l'archive zip du dépôt, débloquez-la **avant** de l'extraire : clic droit sur le fichier zip, Propriétés, cocher « Débloquer », OK. Sinon Windows marque chaque fichier extrait comme provenant d'Internet et affiche un avertissement au lancement, avant même que `Lancer-OffPatch.cmd` puisse retirer cette marque.

## Documentation

- [Cahier des charges](docs/CAHIER-DES-CHARGES.md) : référence fonctionnelle et technique.
- [Points de recherche](docs/RECHERCHE.md) : chaque point vérifié, avec ses sources, ses essais et la décision prise.
- [Backlog et journal](docs/TODO.md) : avancement par phase.
- [Essais](docs/essais/) : procédures de test sur runners GitHub et sur intervention réelle.

## Tests

- `ci.yml` : PSScriptAnalyzer et Pester 5 sous Windows PowerShell 5.1, à chaque push, sans accès réseau (pages du catalogue enregistrées dans `tests/Fixtures`).
- `catalog-contract.yml` : chaque mercredi, vérifie que les pages actuelles du Microsoft Update Catalog sont toujours reconnues et que les liens de téléchargement du moment restent sur les domaines autorisés. Sur un dépôt public, GitHub désactive les workflows planifiés après 60 jours sans activité dans le dépôt : il faut alors réactiver `catalog-contract.yml` dans l'onglet Actions.
- Les essais qui modifient le système (DISM, Defender, installation d'Office) tournent uniquement sur des runners GitHub hébergés et jetables, en déclenchement manuel. Ce que les runners ne permettent pas (redémarrages, Windows 10, Windows 11 x64 client) est validé sur intervention réelle.

## Licence

Code et documentation sous licence [MIT](LICENSE).

Exception : les pages du Microsoft Update Catalog enregistrées dans `tests/Fixtures/catalog/` appartiennent à Microsoft. Elles servent uniquement aux tests automatisés et ne sont pas couvertes par la licence MIT.

OffPatch est un projet indépendant, non affilié à Microsoft. Windows, Office et Defender sont des marques de Microsoft.
