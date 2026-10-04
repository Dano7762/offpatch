# OffPatch

Outil Windows portable qui télécharge une fois par mois les mises à jour Windows, .NET, les définitions Defender et les sources Office, puis les installe sans connexion sur des PC traités un par un (atelier, intervention chez un client). Il remplace WSUS Offline Update, qui n'est plus maintenu.

La référence fonctionnelle et technique est `docs/CAHIER-DES-CHARGES.md`. Ce fichier ne contient que les règles de travail.

## Déroulement d'une session

1. Lire `docs/TODO.md` et repérer la première tâche non cochée de la phase en cours.
2. Si la tâche dépend d'un point encore « À vérifier » dans `docs/RECHERCHE.md`, traiter ce point d'abord.
3. Mener la tâche jusqu'au bout : code, tests Pester, PSScriptAnalyzer sans erreur.
4. Cocher la tâche, ajouter une ligne au journal en bas de `docs/TODO.md`, faire un commit.

Je (David) préfère que tu prennes toi-même les décisions de structure tant qu'elles restent dans le cahier des charges. Ne me demande une validation que si le cahier des charges ne dit rien et que le choix serait coûteux à défaire. Dans ce cas, présente l'option que tu recommandes et pourquoi.

Réponds-moi en français.

## Règles de sécurité (non négociables)

- Ne jamais exécuter sur la machine de développement une opération qui modifie le système : DISM en ligne, wusa, mpam-fe.exe, `setup.exe /configure`, création de tâche planifiée, écriture dans HKLM, redémarrage. Ces chemins de code se testent avec des mocks Pester.
- Les tests réels passent par GitHub Actions, sur le dépôt privé `Dano7762/offpatch`, dans ces limites strictes :
  - les opérations qui modifient le système ne sont autorisées que dans des jobs sur runners hébergés par GitHub (jetables) ; jamais sur un runner auto-hébergé, jamais sur ma machine ;
  - les workflows lourds (téléchargement de cumulatives, installation) se déclenchent uniquement à la main (`workflow_dispatch`) ; seul `ci.yml` (analyse statique et tests) tourne à chaque push ;
  - aucun secret ni clé de produit dans les workflows, les scripts de `tests/runner/` ou les artefacts ;
  - avec `gh`, tu peux pousser sur ce dépôt, lancer des workflows, lire leurs journaux et récupérer leurs artefacts. Rien d'autre sur mon compte GitHub.
- Ce que les runners ne permettent pas (redémarrage, mode auto, Windows 11 x64 client, Windows 10 ESU, support sans checkpoint) est validé sur intervention réelle, en commençant par l'action `Plan` en lecture seule.
- Les fonctions en lecture seule (détection, interrogation du catalogue) peuvent tourner sur la machine de développement.
- Pour tester le téléchargement, utiliser `-ListOnly` (interroge le catalogue sans rien télécharger) ou la cible la plus légère (définitions Defender). Ne télécharger une cumulative complète ou une source Office que si je le demande.
- Toute fonction qui modifie le système ou le dépôt déclare `[CmdletBinding(SupportsShouldProcess)]` et respecte `-WhatIf`.
- Une clé de produit n'est jamais écrite dans un fichier persistant ni dans un journal. Elle reste en mémoire et dans le XML temporaire d'installation, supprimé juste après.
- Aucune activation en dehors des mécanismes Microsoft officiels. Pas de KMS tiers, pas de contournement de licence.
- Téléchargements uniquement depuis les domaines listés dans `config/settings.json` (`allowedDomains`).
- Aucun numéro de KB, titre de catalogue, product ID Office ou URL de téléchargement en dur dans le code. Ils vivent dans `config/` ou dans `depot/manifest.json`.
- Ne jamais inventer un titre de catalogue, un product ID, une URL ou un comportement de DISM ou de l'ODT. Vérifier dans la documentation Microsoft et consigner la source dans `docs/RECHERCHE.md`.

## Contraintes techniques

- Tout le code livré tourne sous Windows PowerShell 5.1, sur x64 et ARM64. Le PC client sort d'installation : rien d'autre n'y est disponible.
- Syntaxe interdite car absente de PowerShell 5.1 : opérateur ternaire, `??` et `??=`, `&&` et `||` entre commandes, `ForEach-Object -Parallel`, `Join-Path` avec plusieurs enfants (`-AdditionalChildPath`), `ConvertFrom-Json -AsHashtable`, `Get-Content -AsByteStream`.
- Fichiers `.ps1`, `.psm1` et `.psd1` enregistrés en UTF-8 avec BOM. Sans BOM, PowerShell 5.1 les lit en ANSI et les libellés français sont cassés. Les `.json` et `.xaml` sont en UTF-8 et toujours lus avec `-Encoding UTF8`.
- Aucune dépendance à installer sur le PC client. Les dépendances côté téléchargement (MSCatalogLTS) sont embarquées dans `lib/` avec une version figée et leur licence.
- Les chemins sont toujours relatifs à la racine de l'outil, retrouvée grâce au fichier marqueur `offpatch.root`. Jamais de lettre de lecteur en dur : le support peut changer de lettre d'un PC à l'autre et même entre deux redémarrages.
- `Set-StrictMode -Version Latest` dans le module, `-ErrorAction Stop` sur les appels qui peuvent échouer, erreurs traitées par `try/catch` et journalisées.
- Le manifeste et les fichiers d'état s'écrivent de façon atomique (fichier temporaire puis renommage).

## Organisation du code

- Toute la logique est dans le module `app/module/OffPatch/` : une fonction exportée par fichier dans `Public/`, les fonctions internes dans `Private/`.
- Préfixe des noms de fonctions : `Op` (`Get-OpSystemInfo`, `Invoke-OpDepotUpdate`). Verbes approuvés uniquement (`Get-Verb`).
- L'interface WPF (`app/gui/`) ne fait que l'affichage et le câblage des événements. Elle appelle les fonctions du module, jamais DISM ou l'ODT directement.
- Tout traitement long (téléchargement, installation, copie) tourne dans un runspace séparé. L'interface est mise à jour via le `Dispatcher` à partir d'une file de messages. Le thread de l'interface ne doit jamais se bloquer.
- `app/OffPatch-Cli.ps1` expose les mêmes opérations sans interface. Il sert à la reprise après redémarrage, au débogage et aux tests.
- Identifiants (fonctions, variables, clés JSON) en anglais. Commentaires, libellés d'interface, messages de journal et rapports en français.
- Aide intégrée (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) pour chaque fonction publique.

## Commandes

Le terminal de Claude Code peut être Git Bash : passer par `powershell.exe`.

```bash
# Tests unitaires
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path ./tests -Output Detailed"

# Analyse statique
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-ScriptAnalyzer -Path ./app -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"

# Opérations sans interface (exemples)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./app/OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./app/OffPatch-Cli.ps1 -Action Plan
```

Pester 5 et PSScriptAnalyzer sont des outils de développement. L'outil livré ne doit jamais en dépendre.

## Git

- Exclus du dépôt git : `depot/`, `rapports/`, `logs/`, `scratch/`, les binaires de `tools/`.
- Dépôt distant : `Dano7762/offpatch` (privé), branche `master`.
- `tests/runner/` contient les scripts exécutés sur les runners GitHub. Mêmes conventions que `app/` (PowerShell 5.1, UTF-8 avec BOM, PSScriptAnalyzer). Jamais livrés avec l'outil.
- Un commit par tâche terminée, message en français préfixé par la phase : `P2: sélection des cumulatives Windows 11 dans le catalogue`.

## Documents à tenir à jour

- `docs/TODO.md` : avancement et journal des sessions.
- `docs/RECHERCHE.md` : chaque point vérifié, avec la source, la date de vérification et la décision prise.
- `docs/CAHIER-DES-CHARGES.md` : à ne modifier qu'après mon accord sur un changement de périmètre. Noter chaque modification dans la section « Historique ».

## Commandes personnalisées

- `/suite` : reprend le projet à la prochaine tâche du backlog.
- `/verif` : lance l'analyse statique et les tests, puis corrige.
- `/recherche R-xx` : traite un point de `docs/RECHERCHE.md`.
