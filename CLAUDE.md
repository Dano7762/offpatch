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
- Les tests réels passent par GitHub Actions, sur le dépôt `Dano7762/offpatch` (public depuis le 2026-10-06 : tout ce qui est poussé est visible de tous), dans ces limites strictes :
  - les opérations qui modifient le système ne sont autorisées que dans des jobs sur runners hébergés par GitHub (jetables) ; jamais sur un runner auto-hébergé, jamais sur ma machine ;
  - les workflows lourds (téléchargement de cumulatives, installation) se déclenchent uniquement à la main (`workflow_dispatch`) ; seul `ci.yml` (analyse statique et tests, sans accès réseau) tourne à chaque push ; `catalog-contract.yml` (contrat en ligne avec le catalogue, lecture seule) tourne chaque mercredi et à la demande ;
  - aucun secret ni clé de produit dans les workflows, les scripts de `tests/runner/` ou les artefacts. Seule exception (décision de David du 2026-10-06) : une clé publique de test publiée par Microsoft, comme la GVLK d'Office LTSC (page Learn « GVLKs for KMS and Active Directory-based activation of Office »), dans un script d'essai de `tests/runner/` uniquement, jamais dans le code d'OffPatch ni dans un workflow ;
  - avec `gh`, tu peux pousser sur ce dépôt, lancer des workflows, lire leurs journaux et récupérer leurs artefacts. Rien d'autre sur mon compte GitHub ;
  - ne pas utiliser `gh run watch` (il a épuisé la limite de l'API GitHub) : interroger l'état des runs au plus une fois toutes les 5 minutes.
- Aucune opération DISM d'analyse ou de maintenance du magasin de composants (`/AnalyzeComponentStore`, `/StartComponentCleanup`, `/ResetBase`…) quand un redémarrage est en attente, ni dans les essais ni dans l'exécuteur d'OffPatch : elle peut bloquer des heures (R-12).
- Ce que les runners ne permettent pas (redémarrage, mode auto, Windows 11 x64 client, Windows 10 ESU, support sans checkpoint) est validé sur intervention réelle, en commençant par l'action `Plan` en lecture seule.
- Les fonctions en lecture seule (détection, interrogation du catalogue) peuvent tourner sur la machine de développement.
- Pour tester le téléchargement, utiliser `-ListOnly` (interroge le catalogue sans rien télécharger) ou le plus petit élément épinglé de `config/pinned-items.json` (enablement package, environ 180 Ko). Ne télécharger une cumulative complète ou une source Office que si je le demande.
- Toute fonction qui modifie le système ou le dépôt déclare `[CmdletBinding(SupportsShouldProcess)]` et respecte `-WhatIf`.
- OffPatch installe uniquement des mises à jour : il n'installe jamais Windows ni Office, ne gère aucune clé de produit, ne touche à aucune activation et ne retire aucun produit.
- Téléchargements uniquement depuis les domaines listés dans `config/settings.json` (`allowedDomains`).
- Aucun numéro de KB, titre de catalogue, product ID Office ou URL de téléchargement en dur dans le code. Ils vivent dans `config/` ou dans `depot/manifest.json`.
- Ne jamais inventer un titre de catalogue, un product ID, une URL ou un comportement de DISM ou de l'ODT. Vérifier dans la documentation Microsoft et consigner la source dans `docs/RECHERCHE.md`.

## Contraintes techniques

- Tout le code livré tourne sous Windows PowerShell 5.1, sur x64 et ARM64. Le PC client sort d'installation : rien d'autre n'y est disponible.
- Syntaxe interdite car absente de PowerShell 5.1 : opérateur ternaire, `??` et `??=`, `&&` et `||` entre commandes, `ForEach-Object -Parallel`, `Join-Path` avec plusieurs enfants (`-AdditionalChildPath`), `ConvertFrom-Json -AsHashtable`, `Get-Content -AsByteStream`.
- Fichiers `.ps1`, `.psm1` et `.psd1` enregistrés en UTF-8 avec BOM. Sans BOM, PowerShell 5.1 les lit en ANSI et les libellés français sont cassés. Les `.json` et `.xaml` sont en UTF-8 et toujours lus avec `-Encoding UTF8`.
- Aucune dépendance à installer sur le PC client, ni de module tiers côté téléchargement : le Microsoft Update Catalog est interrogé par les fonctions du module (R-11).
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
- Configuration : `config/settings.json`, `catalog-queries.json`, `pinned-items.json`, `office/sources.json`, validés par `Test-OpConfiguration` ; tout nouveau champ y est contrôlé et décrit au chapitre 6 du cahier des charges.
- Tests : `tests/Unit` (sans réseau, mocks), `tests/Live` (tag `Live`, catalogue en ligne), `tests/Fixtures` (pages réelles, rafraîchies par `tests/Fixtures/catalog/Save-CatalogFixture.ps1`), `tests/runner` (scripts des workflows).

## Commandes

Le terminal de Claude Code peut être Git Bash : passer par `powershell.exe`. Commandes à lancer depuis la racine du dépôt.

Outils de développement : Pester 5.9.1 et PSScriptAnalyzer 1.25.0, les versions figées de `ci.yml`. Windows fournit d'office Pester 3.4, incompatible avec les tests et chargé par défaut : chaque commande ci-dessous demande donc la version exacte, et cherche d'abord dans `scratch/modules` (hors git), puis dans les modules installés. Sur un nouveau poste, une seule fois après le clonage, sans droits d'administrateur ni dépendance au dossier Documents (si Windows demande le fournisseur NuGet, accepter) :

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '[Net.ServicePointManager]::SecurityProtocol = "Tls12"; New-Item -ItemType Directory -Force ./scratch/modules | Out-Null; Save-Module -Name Pester -RequiredVersion 5.9.1 -Path ./scratch/modules -Repository PSGallery; Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Path ./scratch/modules -Repository PSGallery'
```

```bash
# Tests unitaires (sans le contrat en ligne, comme ci.yml)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'if (Test-Path ./scratch/modules) { $env:PSModulePath = (Resolve-Path ./scratch/modules).Path + ";" + $env:PSModulePath }; Import-Module Pester -RequiredVersion 5.9.1 -ErrorAction Stop; $c = New-PesterConfiguration; $c.Run.Path = "./tests"; $c.Filter.ExcludeTag = "Live"; $c.Output.Verbosity = "Detailed"; Invoke-Pester -Configuration $c'

# Contrat en ligne avec le catalogue (lecture seule), lancé à part
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'if (Test-Path ./scratch/modules) { $env:PSModulePath = (Resolve-Path ./scratch/modules).Path + ";" + $env:PSModulePath }; Import-Module Pester -RequiredVersion 5.9.1 -ErrorAction Stop; $c = New-PesterConfiguration; $c.Run.Path = "./tests/Live"; $c.Filter.Tag = "Live"; $c.Output.Verbosity = "Detailed"; Invoke-Pester -Configuration $c'

# Analyse statique (app et tests, comme ci.yml)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'if (Test-Path ./scratch/modules) { $env:PSModulePath = (Resolve-Path ./scratch/modules).Path + ";" + $env:PSModulePath }; Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop; foreach ($p in "./app", "./tests") { Invoke-ScriptAnalyzer -Path $p -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 }'

# Opérations sans interface (exemples)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./app/OffPatch-Cli.ps1 -Action DepotUpdate -ListOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./app/OffPatch-Cli.ps1 -Action Plan
```

Pester 5 et PSScriptAnalyzer sont des outils de développement. L'outil livré ne doit jamais en dépendre.

Avant chaque push, sans exception : tests Pester (hors tag `Live`, comme `ci.yml`) et PSScriptAnalyzer en local, sans erreur. La CI ne remplace pas cette vérification. Jamais de push avec un test en échec. Le contrat en ligne (tag `Live`) se lance à part et ne conditionne pas le push.

Les fichiers se modifient avec l'outil d'édition natif, pas avec des scripts Python générés. Si un script est indispensable, il va dans `scratch/`. Relire les lignes modifiées avant chaque push.

## Pièges connus

- L'outil Write crée les fichiers sans BOM : remettre le BOM UTF-8 à tout nouveau `.ps1`/`.psm1`/`.psd1`.
- Tests qui chargent des fonctions par dot-source : `Set-StrictMode -Version Latest` dans `BeforeAll`, comme le module, sinon un bug de StrictMode passe les tests et casse en réel.
- `Should -Invoke` sur des appels faits dans `BeforeAll` : ajouter `-Scope Context`.
- Mock d'une cmdlet à paramètre typé (BitsTransfer) : `Mock Remove-BitsTransfer -RemoveParameterType BitsJob {}`.
- Le test « rien en dur » (`Socle.Tests.ps1`) lit aussi les commentaires de `app/` : aucun numéro de KB ni URL, même en exemple (`KB<n>`).
- La CLI ne voit que les fonctions de `Public/` : tout ce qu'elle appelle doit être public.
- Sortie de `powershell.exe` dans Git Bash en CP850 : `| iconv -f CP850 -t UTF-8` ; dans les motifs des tests de la CLI, `.` à la place des lettres accentuées.
- Aide intégrée : une ligne qui commence par un point (« .NET … ») est lue comme un mot-clé inconnu et invalide toute l'aide de la fonction (`Socle.Tests.ps1` échoue sur `.SYNOPSIS`). Reformuler pour que la ligne commence autrement.
- `expand.exe -F:<motif>` est ignoré sur un cabinet d'un seul fichier (décompressé sous son propre nom) : un .msu ou un .cab de test fabriqué avec makecab doit contenir au moins deux fichiers (`DepotUpdate.Tests.ps1`). Dans Git Bash, `expand` désigne l'outil GNU : appeler `%SystemRoot%\System32\expand.exe`.
- Runners de `ci.yml` : Windows Server (contrôle « Système pris en charge » bloquant), langue anglaise (séparateur décimal `.`), extraction git en CRLF (`autocrlf`) : un test ne suppose ni la langue, ni les fins de ligne, ni un Windows client. Échecs vus de la CI du 18 au 22 octobre sans être remarqués : lire le résultat de `ci.yml` après chaque push (`gh run list --workflow ci.yml --limit 1`).
- Tests HTTP : `HttpListener` sur `http://localhost:<port>/` fonctionne sans droits d'administrateur (`Download.Tests.ps1`).
- Interface WPF : pas de `.GetNewClosure()` dans un gestionnaire d'événement ou un bloc relayé par `Register-OpBackgroundPump` (module dynamique : les fonctions de `app/gui/` y sont invisibles). Passer la fenêtre par `Tag` (`$this.Tag`) ou par `-Context` (second argument du bloc).
- Fonction factice de test : ne pas déclarer `[switch]$Confirm` à la main, la règle `PSUseSupportsShouldProcess` fait planter PSScriptAnalyzer (« Reference Position should begin before start Position ») ; mettre `[CmdletBinding(SupportsShouldProcess)]`.
- Fichiers de `config/` réécrits par l'outil : ne modifier que les lignes concernées (`Set-OpDepotSelection`), jamais `ConvertTo-Json` (PowerShell 5.1 réindente tout et échappe `&`).
- Scripts d'essai de `scratch/` avec accents : BOM UTF-8 aussi, sinon un motif comme `'Relevé*'` ne correspond plus.
- Essais sur les VM VirtualBox de David : pas de dépôt lu par le passage USB (SHA-256 faux, différents à chaque lecture) ; dossier partagé puis `robocopy` vers `C:\OffPatch`, en excluant `depot\office` par son chemin complet (`/XD office` écarte aussi `config\office`).

## Git

- Exclus du dépôt git : `depot/`, `rapports/`, `logs/`, `scratch/`, `graphify-out/`, les binaires de `tools/`.
- Dépôt distant : `Dano7762/offpatch` (public, licence MIT), branche `master`.
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
