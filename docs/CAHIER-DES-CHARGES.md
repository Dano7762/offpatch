# OffPatch : cahier des charges

Version 1.12 du 5 octobre 2026.

## 1. Contexte

J'utilisais WSUS Offline Update pour télécharger une seule fois les mises à jour Windows et Office, puis les installer sur des PC fraîchement installés sans tout retélécharger à chaque fois. L'outil n'est plus en état de servir. La dernière version stable de la Community Edition (12.6.1) date de décembre 2021. Un fork a sorti des bêtas 12.7 en février 2025 pour Windows 11 24H2, mais elles reposent sur des listes de liens statiques à maintenir à la main. Le volet Office ne gère que les versions MSI, qui ne sont plus supportées.

La maintenance de Windows a changé et rend un outil plus simple possible :

- Windows 11 24H2, 25H2 et 26H2 partagent la même branche de maintenance et reçoivent les mêmes cumulatives mensuelles. La 26H2 est sortie le 29 septembre 2026 sous forme d'enablement package. Les éditions Famille et Professionnel de la 24H2 ne reçoivent plus de mises à jour après le 13 octobre 2026.
- Windows 10 22H2 est sorti du support le 14 octobre 2025. Le 25 juin 2026, Microsoft a prolongé l'ESU grand public jusqu'au 12 octobre 2027. L'ESU commercial peut aller jusqu'au 10 octobre 2028.
- Office 2016 et 2019 ne sont plus supportés depuis octobre 2025. Office 2021 et 2024, en boîte comme en LTSC, sont en Click-to-Run et se déploient avec l'Office Deployment Tool (ODT).

Pour chaque cible, il y a donc chaque mois une poignée de fichiers : la cumulative Windows et ses éventuels prérequis, la cumulative .NET, les définitions Defender et, pour Office, une source par canal.

Usage visé : je prépare les PC un par un, à l'atelier ou chez le client. Il n'y a ni parc à gérer, ni serveur, ni réseau à exploiter.

## 2. Objectifs

1. Télécharger une fois par mois et installer sur autant de PC que nécessaire sans retélécharger.
2. Un PC fraîchement installé ressort à jour : Windows, .NET, Defender, et Office installé dans sa dernière build.
3. Le même outil sert dans deux situations :
   - le dépôt est mis à jour sur mon poste, puis copié sur un support (clé ou SSD) ;
   - le support est autonome : on y lance aussi le téléchargement, depuis n'importe quel PC connecté.
4. Deux modes d'installation au choix : automatique, avec redémarrages et reprise gérés, ou manuel, étape par étape.
5. Chaque intervention laisse un rapport par PC.

## 3. Périmètre

### 3.1 Systèmes cibles

| Code cible | Système | Versions | Architecture | Remarque |
|---|---|---|---|---|
| `win11-x64` | Windows 11 | 24H2, 25H2, 26H2 | x64 | Branche de maintenance commune |
| `win11-arm64` | Windows 11 | 24H2, 25H2, 26H2 | ARM64 | Tests sur matériel réel uniquement |
| `win10-x64` | Windows 10 | 22H2 (build 19045) | x64 | Seulement si l'ESU est actif sur le PC |

Tout le reste est détecté puis refusé avec un message clair, sans rien installer : Windows 11 23H2 et antérieurs, Windows 10 avant 22H2, x86, Windows Server, Windows 11 26H1 (plateforme différente, réservée à certains PC ARM).

### 3.2 Contenus gérés

| Code catégorie | Contenu | Cibles | Source |
|---|---|---|---|
| `windows-checkpoint` | Cumulatives « checkpoint » prérequises | Windows 11 | Microsoft Update Catalog |
| `windows-ssu` | Mise à jour autonome de la pile de maintenance (SSU), prérequise sur les images anciennes | Windows 10 | Élément épinglé (`config/pinned-items.json`) |
| `windows-lcu` | Dernière cumulative Windows | Toutes | Microsoft Update Catalog |
| `windows-ekb` | Enablement package 26H2 | Windows 11 24H2 et 25H2 | Élément épinglé (`config/pinned-items.json`) : lien direct Microsoft, l'enablement package n'est pas indexé au catalogue (R-03) |
| `dotnet` | Cumulative .NET Framework | Toutes | Microsoft Update Catalog |
| `defender-platform` | Mise à jour de la plateforme Microsoft Defender (KB4052623) | Toutes | Microsoft Update Catalog, canal « Current Channel (Broad) » uniquement |
| `defender` | Définitions Microsoft Defender (mpam-fe.exe) | Toutes | Lien de téléchargement Microsoft |
| `office-source` | Source d'installation Office par canal | Toutes | ODT `/download` |

Les points encore incertains (titres exacts du catalogue, prérequis checkpoint, enablement package, ESU) sont listés dans `RECHERCHE.md` et tranchés en phase 0.

### 3.3 Éditions Office

| Profil | Libellé | Product ID | Canal | Licence | Windows 10 22H2 |
|---|---|---|---|---|---|
| `home2024` | Office Famille 2024 | `Home2024Retail` | Current | Compte Microsoft du client | Non pris en charge |
| `homebusiness2024` | Office Famille et Petite Entreprise 2024 | `HomeBusiness2024Retail` | Current | Compte Microsoft du client | Non pris en charge |
| `homestudent2021` | Office Famille et Étudiant 2021 | `HomeStudent2021Retail` | Current | Compte Microsoft du client | Non pris en charge |
| `homebusiness2021` | Office Famille et Petite Entreprise 2021 | `HomeBusiness2021Retail` | Current | Compte Microsoft du client | Non pris en charge |
| `ltsc2024-proplus` | Office LTSC Professionnel Plus 2024 | `ProPlus2024Volume` | PerpetualVL2024 | Clé MAK | Non pris en charge |
| `ltsc2024-std` | Office LTSC Standard 2024 | `Standard2024Volume` | PerpetualVL2024 | Clé MAK | Non pris en charge |
| `ltsc2021-proplus` | Office LTSC Professionnel Plus 2021 | `ProPlus2021Volume` | PerpetualVL2021 | Clé MAK | Non pris en charge |
| `ltsc2021-std` | Office LTSC Standard 2021 | `Standard2021Volume` | PerpetualVL2021 | Clé MAK | Non pris en charge |

Les huit product IDs figurent dans la liste officielle de l'ODT (R-07). Les quatre profils en boîte utilisent le canal Current et partagent une seule source `current` : leur build est celle du Current Channel (R-07).

Prise en charge sous Windows 10 22H2, d'après les configurations requises de Microsoft (« Office suites for individuals and families » et « Office suites for enterprise, business, education, and government », support.microsoft.com, consultées le 4 octobre 2026) : Office 2024 et Office 2021 en boîte ne citent que Windows 11 ; Office LTSC 2024 et LTSC 2021 citent Windows 11, Windows 11 LTSC 2024, Windows 10 LTSC 2021 et 2019 et des versions de Windows Server, pas Windows 10 22H2. L'installation reste possible, mais elle se fait hors du support Microsoft : l'outil le signale sans la bloquer (8.2, 8.6, 8.8). La liste est tenue à jour dans `profiles.json` (champ `supportedOn`), avec la source.

Une source Office correspond à un canal et à une liste de langues. Il en faut donc trois au maximum : `current`, `perpetualvl2024`, `perpetualvl2021`. Office est installé en 64 bits, y compris sur les PC ARM64 (R-07). Langues par défaut : `fr-fr` et `en-us` pour la source `current`, `fr-fr` pour les sources LTSC (6.1). La liste des langues est réglable par source, mais l'installation ne peut utiliser que des langues présentes dans la source, puisque le repli sur le CDN est désactivé.

### 3.4 Hors périmètre de la v1

- Gestion de parc, déploiement réseau, serveur WSUS.
- Pilotes, runtimes Visual C++, logiciels tiers.
- Activation, en dehors de la saisie facultative d'une clé MAK pour les profils LTSC.
- Microsoft 365 Apps (abonnement). Le mécanisme serait le même, voir la section 14.
- Création ou modification d'ISO.
- Mises à niveau de version majeure (Windows 11 23H2 vers 24H2, Windows 10 vers 11). Elles passent par une ISO récente.
- Windows Server, Windows x86, Office 32 bits.
- Ouverture de session automatique après redémarrage.

## 4. Principes d'architecture

1. Un seul outil avec deux faces. La face Dépôt télécharge et a besoin d'Internet. La face Installation applique les mises à jour et ne contacte jamais Internet.
2. Le manifeste `depot/manifest.json` est le contrat entre les deux faces. L'installation ne lit que lui et les fichiers qu'il référence.
3. Toute la logique vit dans un module PowerShell. L'interface WPF et le script en ligne de commande ne sont que deux façades sur ce module.
4. L'outil est portable. Sa racine est retrouvée grâce au fichier marqueur `offpatch.root` et le dépôt ne stocke aucun chemin absolu.
5. Les données qui changent avec Microsoft (titres du catalogue, product IDs, URL, domaines) sont dans `config/`. Le code n'en contient aucune.
6. Windows PowerShell 5.1, x64 et ARM64, aucune installation sur le PC client.

## 5. Arborescence

```text
OffPatch/
├── Lancer-OffPatch.cmd            Point d'entrée : élévation UAC, stratégie d'exécution contournée
├── offpatch.root                  Fichier marqueur de la racine (contient un identifiant d'installation)
├── CLAUDE.md
├── README.md
├── PSScriptAnalyzerSettings.psd1
├── app/
│   ├── OffPatch.ps1               Lance l'interface WPF (paramètre -Resume pour la reprise)
│   ├── OffPatch-Cli.ps1           Mêmes opérations sans interface
│   ├── resume.ps1                 Amorce de reprise, copiée dans ProgramData avant un redémarrage
│   ├── module/OffPatch/
│   │   ├── OffPatch.psd1
│   │   ├── OffPatch.psm1
│   │   ├── Public/                Une fonction exportée par fichier
│   │   └── Private/
│   └── gui/
│       ├── MainWindow.xaml
│       ├── Dialogs/               Récapitulatif du mode auto, préparation de support, attente du support
│       └── *.ps1                  Câblage des événements
├── config/
│   ├── settings.json
│   ├── catalog-queries.json
│   ├── pinned-items.json
│   └── office/
│       ├── profiles.json
│       ├── download.xml.template
│       └── install.xml.template
├── lib/
│   └── MSCatalogLTS/<version>/    Module figé et sa licence
├── tools/
│   └── odt/                       setup.exe de l'ODT, récupéré par l'outil (hors git)
├── depot/                         Données téléchargées (hors git)
│   ├── manifest.json
│   ├── files/                     Fichiers Windows, .NET et Defender, dédoublonnés
│   │   └── <sha256>/              Un dossier par fichier, nommé par son SHA-256
│   │       └── <nom d'origine>    ex. windows11.0-kb5129195-x64_<sha1>.msu
│   └── office/                    current/ perpetualvl2024/ perpetualvl2021/
├── rapports/                      Rapports d'intervention, un par PC (hors git)
├── logs/                          Journaux de la face Dépôt (hors git)
├── scratch/                       Scripts jetables de la phase de recherche (hors git)
├── tests/
│   ├── Unit/
│   ├── Fixtures/                  Manifestes, sorties DISM et registres simulés
│   └── runner/                    Scripts exécutés sur les runners GitHub (jamais livrés)
├── .github/
│   └── workflows/                 ci.yml, essais sur runners hébergés
└── docs/
    ├── CAHIER-DES-CHARGES.md
    ├── RECHERCHE.md
    └── TODO.md
```

Chaque fichier Windows, .NET ou Defender est rangé seul dans un dossier nommé par son SHA-256, sous son nom d'origine. Un fichier partagé par plusieurs éléments du manifeste (par exemple une cumulative checkpoint jointe à chaque cumulative) n'est stocké qu'une fois. Le dossier ne contient jamais d'autre fichier : DISM cherche les checkpoints dans le dossier du paquet qu'on lui passe et traite toutes les cumulatives qu'il y trouve (R-02).

Sur le PC client, l'outil écrit uniquement dans `C:\ProgramData\OffPatch\` : `state.json`, `resume.ps1`, `temp\` (XML Office générés) et `logs\`. Tout est nettoyé en fin de session, sauf les journaux.

## 6. Configuration

### 6.1 `config/settings.json`

```json
{
  "schemaVersion": 1,
  "targets": ["win11-x64", "win11-arm64", "win10-x64"],
  "windows": {
    "includeEnablementPackage": true
  },
  "office": {
    "sources": {
      "current": { "languages": ["fr-fr", "en-us"] },
      "perpetualvl2024": { "languages": ["fr-fr"] },
      "perpetualvl2021": { "languages": ["fr-fr"] }
    },
    "clientEdition": "64"
  },
  "retention": {
    "windowsMonths": 2,
    "officeVersions": 1
  },
  "client": {
    "minFreeSpaceGB": 20,
    "maxAutoReboots": 5,
    "rebootCountdownSeconds": 30,
    "staleDepotWarningDays": 35,
    "pauseWindowsUpdateDuringSession": true,
    "odtTimeoutMinutes": 30
  },
  "logging": {
    "level": "INFO"
  },
  "allowedDomains": [
    "catalog.update.microsoft.com",
    "download.windowsupdate.com",
    "download.microsoft.com",
    "go.microsoft.com",
    "officecdn.microsoft.com"
  ]
}
```

Les valeurs chiffrées sont des valeurs de départ. La liste `allowedDomains` sera complétée en phase 0 avec les domaines réellement atteints après redirection (R-13). Elle s'applique aux téléchargements faits par OffPatch lui-même (catalogue, mpam-fe.exe, plateforme Defender, éléments épinglés, ODT). Elle ne s'applique pas au trafic propre de l'ODT pendant `setup.exe /download`, qui contacte ses propres domaines (CDN Office, mais aussi par exemple `ecs.office.com` ou `mrodevicemgr.officeapps.live.com`) : OffPatch ne le contrôle pas, il se contente de le journaliser. L'interface modifie ce fichier quand je change les cibles ou les langues dans l'onglet Dépôt.

Les langues se règlent par source Office. Par défaut, la source `current` porte `fr-fr` et `en-us` : les Office en boîte ou Microsoft 365 préinstallés par les fabricants sont souvent bilingues, et une langue installée absente de la source empêche leur mise à jour (8.5, R-08). L'anglais ajoute environ 350 Mo à la source Current (3 955 Mo au lieu de 3 605 Mo, mesuré le 5 octobre 2026). Les sources `perpetualvl2024` et `perpetualvl2021` portent `fr-fr` seul.

### 6.2 `config/catalog-queries.json`

Pour chaque cible et chaque catégorie : la recherche à envoyer au catalogue, un motif d'inclusion et un motif d'exclusion sur le titre, la règle de sélection. Le motif d'exclusion écarte au minimum les préversions, les mises à jour dynamiques, les hotpatchs, les éditions Server et les mauvaises architectures.

Exemple de forme (les chaînes réelles sont établies en R-01) :

```json
{
  "win11-x64": [
    {
      "category": "windows-lcu",
      "search": "Cumulative Update Windows 11 x64",
      "includeTitlePattern": "Cumulative Update for Windows 11.*x64-based",
      "excludeTitlePattern": "Preview|Dynamic|Hotpatch|Server|\\.NET|arm64",
      "pick": "latest"
    }
  ]
}
```

Quand Microsoft change la formulation d'un titre, on corrige ce fichier sans toucher au code.

Une entrée peut porter les champs de dépendance `prerequisites` et `runsAfter` décrits en 8.3 ; l'outil les recopie dans les éléments du manifeste. Exemples : la cumulative Windows 11 a pour prérequis la catégorie `windows-checkpoint`, la cumulative Windows 10 la catégorie `windows-ssu` ; les définitions Defender (`defender`) s'exécutent après `defender-platform` (`runsAfter`). Pour `defender-platform`, le motif d'inclusion n'accepte que « Current Channel (Broad) » et le motif d'exclusion écarte `Preview|Staged|Beta` (R-06).

### 6.3 Office

`config/office/profiles.json` décrit les profils du tableau 3.3 :

```json
{
  "id": "ltsc2024-proplus",
  "label": "Office LTSC Professionnel Plus 2024",
  "productId": "ProPlus2024Volume",
  "channel": "PerpetualVL2024",
  "source": "perpetualvl2024",
  "license": "volume",
  "acceptsProductKey": true,
  "excludeApps": [],
  "supportedOn": {
    "windows": ["win11"],
    "source": "https://support.microsoft.com/en-us/office/system-requirements/office-suites-for-enterprise-business-education-and-government"
  }
}
```

`install.xml.template` sert à générer, au moment de l'installation, un XML avec le chemin absolu de la source sur le support :

```xml
<Configuration>
  <Add OfficeClientEdition="64" Channel="{{Channel}}" SourcePath="{{SourcePath}}" AllowCdnFallback="FALSE">
    <Product ID="{{ProductId}}"{{PidKeyAttribute}}>
{{LanguageElements}}
{{ExcludeAppElements}}
    </Product>
  </Add>
{{RemoveElement}}
  <RemoveMSI />
  <Updates Enabled="TRUE" Channel="{{Channel}}" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
```

`AllowCdnFallback="FALSE"` garantit que l'installation n'utilise que la source locale. Les mises à jour ultérieures du PC client restent activées sur le canal normal de Microsoft. La compatibilité de `<Remove>` combiné à `<Add>` dans un même fichier est à vérifier (R-08).

### 6.4 `config/pinned-items.json`

Éléments épinglés : fichiers Microsoft qui ne sont pas indexés au Microsoft Update Catalog mais dont le lien direct est stable, comme l'enablement package 26H2 (R-03). Pour ces catégories, aucune recherche au catalogue.

```json
{
  "items": [
    {
      "id": "win11-x64-ekb-26H2",
      "category": "windows-ekb",
      "kb": "KB0000000",
      "arch": "x64",
      "url": "https://catalog.sf.dl.delivery.mp.microsoft.com/…/windows11.0-kb0000000-x64_<sha1>.msu",
      "sha1": "<empreinte de 40 caractères, identique à celle du nom de fichier>",
      "appliesToBaseBuilds": [26100, 26200],
      "minUbr": 0,
      "resultingBuild": 26300,
      "prerequisites": [],
      "runsAfter": ["windows-lcu"]
    }
  ]
}
```

- Un élément épinglé est téléchargé une fois, puis vérifié : domaine autorisé (`allowedDomains`), SHA-1 égal à la valeur de la configuration et à l'empreinte du nom de fichier, signature Authenticode valide au nom de Microsoft. Un échec de vérification écarte le fichier.
- Il n'est jamais purgé (7.3).
- Le lien est mis à jour à la main, une fois par an, à la sortie d'une nouvelle version de Windows.
- `appliesToBaseBuilds` : builds de base sur lesquelles l'élément s'applique. Champs facultatifs selon la catégorie : `minUbr`, UBR minimal du PC exigé par Microsoft avant l'installation ; `applyBelowUbr`, l'élément n'est utile que si l'UBR du PC est inférieur à cette valeur (SSU autonome des images anciennes) ; `resultingBuild`, build de base obtenue après installation et redémarrage ; `prerequisites` et `runsAfter`, dépendances bloquantes et dépendances d'ordre (8.3).

## 7. Face Dépôt

### 7.1 Mise à jour du dépôt

Pour chaque cible cochée :

1. Vérifier l'accès à Internet et aux domaines autorisés.
2. Interroger le catalogue avec les requêtes de `catalog-queries.json`. MSCatalogLTS ne sert qu'à la recherche et à la résolution des liens. Le téléchargement est fait par l'outil, pour maîtriser la reprise, le dossier temporaire et le contrôle d'intégrité.
3. Comparer avec le manifeste. Un élément déjà présent avec le même hash n'est pas retéléchargé.
4. Télécharger dans `depot/.tmp/` avec BITS (`Start-BitsTransfer`, reprise possible), et un repli sur `HttpClient` en flux si BITS n'est pas disponible.
5. Vérifier l'authenticité, en ligne, au téléchargement, et calculer le SHA-256 (R-10). Critères Authenticode pour les fichiers signés (.msu, .exe, .cab) : `Status` = `Valid`, signataire de l'organisation Microsoft Corporation, chaîne jusqu'à une racine Microsoft (relevé : Microsoft Root Certificate Authority 2010). Un certificat expiré mais horodaté reste valide ; aucun contrôle sur la date d'expiration du certificat. Pour une source Office, le SHA-256 de chaque fichier est enregistré dans le manifeste ; ses fichiers `.dat` ne portent pas de signature Authenticode (ils sont couverts par des catalogues `.dat.cat` signés) et l'ODT les valide lui-même pendant `/download`.
6. Pour une cumulative Windows ou .NET, lire dans le .msu le nom et la version du paquet (fichier `update.mum` du .cab, extrait avec `expand.exe`) et les inscrire dans le manifeste (7.2).
7. Déplacer le fichier à sa place définitive et ajouter l'élément au manifeste.

Ensuite :

- Defender : télécharger la mise à jour de plateforme (KB4052623, recherche au catalogue) et mpam-fe.exe pour chaque architecture, et lire leur version (`FileVersion`).
- Office : vérifier ou récupérer l'ODT dans `tools/odt/`, générer le XML de téléchargement de chaque source (canal et langues), lancer `setup.exe /download`, relever la version obtenue.
- Écrire le manifeste de façon atomique, appliquer la purge, afficher un résumé des nouveautés du mois.

L'option `-ListOnly` fait tout sauf les téléchargements : elle affiche ce qui serait récupéré. Un téléchargement interrompu peut être relancé sans tout reprendre.

### 7.2 Manifeste

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-14T09:12:00Z",
  "toolVersion": "1.0.0",
  "items": [
    {
      "id": "win11-x64-lcu-KB0000000",
      "category": "windows-lcu",
      "target": { "os": "win11", "arch": "x64", "minBuild": 26100, "maxBuild": 26399 },
      "kb": "KB0000000",
      "title": "Titre exact relevé dans le catalogue",
      "releaseDate": "2026-10-13",
      "baseBuilds": [26100, 26200, 26300],
      "resultingUbr": 0,
      "order": 20,
      "requiresReboot": true,
      "prerequisites": ["win11-x64-checkpoint-KB0000001"],
      "runsAfter": [],
      "files": [
        {
          "path": "files/<sha256>/nom-du-fichier.msu",
          "sha256": "…",
          "size": 0,
          "package": { "name": "Package_for_RollupFix", "version": "26100.0000.1.0" }
        }
      ],
      "sourceUrl": "https://catalog.update.microsoft.com/…"
    },
    {
      "id": "win10-x64-dotnet-KB0000002",
      "category": "dotnet",
      "target": { "os": "win10", "arch": "x64", "minBuild": 19045, "maxBuild": 19045 },
      "kb": "KB0000002",
      "title": "Titre exact relevé dans le catalogue",
      "releaseDate": "2026-10-13",
      "order": 40,
      "requiresReboot": false,
      "files": [
        {
          "path": "files/<sha256>/windows10.0-kb0000003-x64-ndp48_<sha1>.msu",
          "sha256": "…",
          "size": 0,
          "package": { "name": "Package_for_DotNetRollup", "version": "10.0.0000.0" },
          "netRelease": { "min": 528040, "max": 533319 }
        },
        {
          "path": "files/<sha256>/windows10.0-kb0000004-x64-ndp481_<sha1>.msu",
          "sha256": "…",
          "size": 0,
          "package": { "name": "Package_for_DotNetRollup_481", "version": "10.0.0000.0" },
          "netRelease": { "min": 533320 }
        }
      ],
      "sourceUrl": "https://catalog.update.microsoft.com/…"
    }
  ]
}
```

Les valeurs ci-dessus illustrent le format. Les chemins dans `files` sont relatifs à `depot/`. Les champs `baseBuilds` et `resultingUbr` servent à la détection des cumulatives Windows. Un même paquet s'applique à plusieurs versions qui partagent une branche de maintenance : chacune a sa build de base (26100 pour 24H2, 26200 pour 25H2, 26300 pour 26H2) et toutes reçoivent le même UBR. `baseBuilds` liste ces builds de base, `resultingUbr` est l'UBR obtenu après installation. Pour Windows 11, l'UBR est relevé dans le titre du catalogue. Pour Windows 10, dont le titre ne porte pas de build, il vient de la correspondance KB → build publiée par Microsoft (page release-information), ce qui permet de sélectionner la cumulative avant tout téléchargement (R-01, R-09). Après téléchargement, la version du paquet lue dans le .msu sert de contre-vérification de `resultingUbr` : en cas de divergence, l'outil écrit un avertissement dans le journal et la valeur lue dans le .msu fait foi pour la détection.

`prerequisites` et `runsAfter` : dépendances bloquantes et dépendances d'ordre (8.3). Chaque valeur est l'identifiant d'un élément ou un code de catégorie ; un code de catégorie désigne tous les éléments de cette catégorie applicables au PC.

`package` (par fichier) : nom et version du paquet lus dans le .msu au téléchargement (7.1). Pour une cumulative .NET, c'est la référence de détection (8.3). `netRelease` (par fichier, cumulatives .NET Windows 10) : plage de la valeur `Release` de .NET Framework 4 pour laquelle le fichier s'applique ; 4.8 de 528040 à 533319, 4.8.1 à partir de 533320 (R-05). Un élément .NET Windows 10 porte les deux fichiers ; l'outil installe celui qui correspond au PC. Une source Office est un élément de catégorie `office-source` avec son canal, sa version, ses langues et le dossier concerné.

### 7.3 Purge

- Cumulatives Windows et .NET : on garde les `retention.windowsMonths` plus récentes par cible (2 par défaut, la courante et la précédente comme solution de repli).
- Defender (définitions et plateforme) : seulement la dernière version de chacune.
- Éléments épinglés (6.4) : jamais purgés.
- Office : seulement la dernière version par source, après avoir vérifié que l'index de la source (`v64.cab`) pointe bien sur elle (R-07).
- Les fichiers étant partagés entre éléments (section 5), un fichier n'est supprimé que lorsque plus aucun élément conservé du manifeste ne le référence (comptage de références).
- La purge ne supprime que des éléments connus du manifeste. Les fichiers orphelins trouvés dans `depot/` sont listés et ne sont supprimés qu'après confirmation.

### 7.4 Préparer un support

Assistant accessible depuis l'onglet Dépôt :

1. Choisir le lecteur de destination (clé ou disque externe).
2. Choisir les cibles et les sources Office à embarquer, pour ne copier que l'utile.
3. Contrôler le système de fichiers : NTFS ou exFAT. Le FAT32 est refusé, car certains fichiers peuvent dépasser 4 Go (R-12). Contrôler l'espace libre.
4. Si le support contient déjà OffPatch, rapatrier d'abord ses rapports dans `rapports/` du poste.
5. Copier `app/`, `config/`, `lib/`, `tools/`, `offpatch.root`, `README.md` et les dossiers du dépôt retenus, avec robocopy en miroir dossier par dossier. Le dossier `rapports/` du support n'est jamais mis en miroir, pour ne pas effacer de rapports.
6. Écrire sur le support un manifeste filtré qui ne contient que les éléments copiés.
7. Vérifier la copie (tailles, puis hash des fichiers du manifeste) et afficher un bilan.

## 8. Face Installation

### 8.1 Lancement

`Lancer-OffPatch.cmd` demande l'élévation, puis lance `powershell.exe -NoProfile -ExecutionPolicy Bypass -File app\OffPatch.ps1`. Au premier lancement depuis un support, l'outil retire la marque « fichier téléchargé » de ses propres fichiers (`Unblock-File`). Tout fonctionne quelle que soit la lettre du lecteur.

### 8.2 Contrôles préalables

| Contrôle | Comportement |
|---|---|
| Droits administrateur | Bloquant |
| Cible reconnue (système, version, build, architecture, édition) | Hors périmètre : bloquant, avec le motif. Windows 10 et Windows 11 se distinguent par `CurrentBuild` (22000 et plus = Windows 11), jamais par `ProductName`, qui vaut encore « Windows 10 … » sur Windows 11. Le libellé affiché vient de `Win32_OperatingSystem.Caption` (R-09) |
| Windows 10 : ESU actif | Absent ou indétectable : avertissement. En mode auto, l'étape Windows est ignorée sauf si je la force dans le récapitulatif (R-04) |
| Profil Office choisi pris en charge par Microsoft sur ce Windows (3.3, `supportedOn`) | Non pris en charge (par exemple tout profil sur Windows 10 22H2) : avertissement non bloquant, avec la source Microsoft ; rappel dans l'écran récapitulatif du mode auto (8.6) et dans le rapport (8.8) |
| Redémarrage en attente (CBS, Windows Update, renommages de fichiers en attente) | Proposer de redémarrer avant de commencer |
| Espace libre sur C: | Sous `minFreeSpaceGB` : bloquant |
| Portable sur batterie | Avertissement, confirmation demandée avant le mode auto |
| Âge du dépôt | Au-delà de `staleDepotWarningDays` : avertissement |
| PC connecté à Internet | Avertissement : Windows Update peut travailler en parallèle. Si `pauseWindowsUpdateDuringSession` est actif, Windows Update est suspendu pendant la session et rétabli à la fin (méthode en R-15) |
| Intégrité des fichiers nécessaires | Hash différent du manifeste : l'étape passe en erreur, les autres continuent |

### 8.3 Détection et plan

Pour chaque élément du manifeste applicable au PC, l'outil calcule un état :

| État (code) | Libellé affiché |
|---|---|
| `UpToDate` | À jour |
| `Pending` | À installer |
| `NotApplicable` | Non applicable |
| `MissingFromDepot` | Absent du dépôt |
| `SkippedPrerequisite` | Ignorée (prérequis) |
| `Error` | Erreur |

Méthodes de détection, à confirmer en R-09. La famille (Windows 10 ou 11) se lit sur `CurrentBuild`, jamais sur `ProductName` (8.2). Pour les cumulatives, la détection repose sur l'UBR ; la liste des paquets DISM ne sert qu'au diagnostic (son nom de paquet porte la build 26100 même sur une 25H2, et une checkpoint y figure à l'état « Staged », R-02) :

- Cumulative Windows : non applicable si la build courante ne figure pas dans `baseBuilds`. Sinon, à jour si l'UBR courant est supérieur ou égal à `resultingUbr`, à installer dans le cas contraire.
- Checkpoint : présente si la build courante est une build de base de la branche (26100, 26200 ou 26300) et que l'UBR courant est supérieur ou égal à l'UBR de la checkpoint (1742 pour KB5043080).
- SSU autonome Windows 10 (élément épinglé, 6.4) : à installer si la build est 19045 et que l'UBR courant est inférieur à `applyBelowUbr` (3271 pour KB5031539, prérequis des images sans KB5028244), non applicable sinon. Une réinstallation est sans effet : l'état se juge sur l'UBR, pas sur le code retour (R-02).
- Enablement package (élément épinglé, 6.4) : non applicable si la build courante ne figure pas dans `appliesToBaseBuilds` (déjà en 26300, ou autre branche) ou si l'option est désactivée ; à installer sinon. Prérequis : UBR du PC supérieur ou égal à `minUbr` (voir les règles de prérequis ci-dessous).
- .NET : à jour si la liste des paquets DISM contient un paquet de même nom que `package.name`, à l'état `Installed`, de version supérieure ou égale à `package.version` ; à installer sinon. Sous Windows 10, le fichier est choisi d'après la valeur `Release` de `HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full` (`netRelease`). `Get-HotFix` ne sert qu'au diagnostic : une cumulative plus récente fait disparaître le KB du dépôt de sa liste (R-05).
- Plateforme Defender : mêmes règles d'applicabilité que les définitions ci-dessous ; à jour si `AMProductVersion` est supérieure ou égale à la version du fichier du dépôt (`FileVersion`), à installer sinon (R-06).
- Defender : applicable si `Get-MpComputerStatus` répond et que `AMRunningMode` indique un Defender actif (`Normal`) ou passif (`Passive Mode`, `EDR Block Mode`). Si Defender est désactivé (antivirus tiers, service arrêté) ou si `Get-MpComputerStatus` échoue, l'étape est non applicable avec son motif dans le rapport, jamais en erreur. Sinon, à jour si `AntivirusSignatureVersion` est supérieure ou égale à la version de mpam-fe.exe (`FileVersion`), à installer dans le cas contraire (R-06).
- Office : registre ClickToRun (produits installés, canal, langues déclarées sous `ProductReleaseIDs`). La version installée est la version de fichier de `WINWORD.EXE`, à défaut `EXCEL.EXE`, puis `POWERPNT.EXE`, dans le dossier tiré de `InstallationPath` (registre Click-to-Run). `VersionToReport` ne sert qu'au diagnostic : il peut annoncer une version que les applications n'ont pas après un échec de l'ODT (R-08). En cas d'écart entre les deux, avertissement dans le rapport, et Office est « À installer ». Avant toute mise à jour ou installation sur un Office existant, les langues installées sont comparées à celles de la source du canal : s'il en manque une, l'étape est `NotApplicable` avec le motif « langue absente de la source », et l'ODT n'est pas lancé (8.5, R-08).

Le plan est la liste ordonnée des étapes, avec les points de redémarrage. Ordre par défaut :

1. Plateforme Defender, puis définitions Defender (pas de redémarrage). La plateforme est une dépendance d'ordre des définitions : si elle échoue, les définitions sont tentées quand même.
2. SSU autonome Windows 10 si nécessaire, checkpoints, puis cumulative Windows, puis redémarrage.
3. Enablement package 26H2 si l'option est active et que l'UBR du PC, après le redémarrage de l'étape 2, est supérieur ou égal à `minUbr` ; puis redémarrage.
4. Cumulative .NET, redémarrage si demandé. Le paquet .NET est le même fichier pour 24H2, 25H2 et 26H2 (R-05) : il ne dépend pas de l'enablement package.
5. Office : installation ou mise à jour.
6. Contrôle final : nouvelle détection et rapport.

Si la phase 0 montre que certaines étapes peuvent s'enchaîner avant un seul redémarrage (R-02, R-03), le planificateur regroupe les redémarrages.

Règles de dépendance. Deux types, déclarés dans le manifeste (7.2) et dans `pinned-items.json` (6.4) :

- **Prérequis bloquant** (`prerequisites`, ou condition comme `minUbr`) : l'étape n'est exécutée que si la condition est remplie. Exemples : l'enablement package exige `minUbr` ; une cumulative Windows 11 exige la checkpoint ; une cumulative Windows 10 sur image ancienne exige le SSU autonome.
- **Dépendance d'ordre** (`runsAfter`) : l'étape est placée après celle dont elle dépend, sans condition sur le résultat de celle-ci. Exemples : les définitions Defender après la plateforme Defender ; l'enablement package après la cumulative Windows (et son redémarrage).
- Un prérequis bloquant qui n'est pas applicable au PC (par exemple le SSU autonome sur un Windows 10 récent) ou déjà à jour est réputé rempli.

Règles de prérequis :

- Un prérequis peut être satisfait par une étape antérieure du même plan. L'UBR projeté après une cumulative prévue est son `resultingUbr` ; c'est lui qui sert à évaluer les étapes suivantes (par exemple l'enablement package et son `minUbr`).
- Juste avant chaque étape, et donc après chaque redémarrage, l'outil revérifie l'état réel du PC (build, UBR, détection de la catégorie) au lieu de se fier au plan.
- Si un prérequis n'est pas rempli, à la planification ou au moment de l'étape, l'étape passe à l'état `SkippedPrerequisite` (« Ignorée (prérequis) ») avec son motif dans le rapport. Les étapes qui en dépendent par un prérequis bloquant sont ignorées de la même façon ; celles qui n'en dépendent que par l'ordre sont exécutées normalement. Le reste du plan continue.

### 8.4 Exécution des étapes Windows

- Installation des paquets par DISM en ligne, sans redémarrage automatique, avec un journal DISM par étape. Le choix entre `dism.exe` et `Add-WindowsPackage` est fait en R-14. Pas de délai maximal sur DISM.
- Juste avant chaque étape, revérification du SHA-256 des seuls fichiers utilisés par l'étape, par rapport au manifeste. Côté client, pas de contrôle Authenticode : l'authenticité a été établie au téléchargement (R-10).
- Codes retour : 0 réussite, 3010 redémarrage nécessaire, « non applicable » (0x800f081e) traité comme `NotApplicable` et non comme une erreur, le reste en erreur avec le code dans le journal et le rapport.
- Plateforme Defender : exécution de `updateplatform.<arch>fre_….exe`, puis attente du retour de Defender en mode `Normal`, bornée à 120 s. En cas de dépassement, avertissement dans le journal, et les définitions sont tentées quand même. Réussite constatée par `AMProductVersion`, pas par le code retour.
- Defender : exécution de mpam-fe.exe, puis lecture de la nouvelle version pour confirmer. Le code retour ne suffit pas : mpam-fe.exe peut renvoyer 0 sans rien appliquer (R-06).

### 8.5 Office

| Situation détectée | Action |
|---|---|
| Aucun Office Click-to-Run | Installation du profil choisi depuis la source locale |
| Autre produit Click-to-Run sur un canal présent dans le dépôt (par exemple Microsoft 365 Famille préinstallé, canal Current) | Par défaut : conservé et mis à jour depuis la source locale. Option dans le récapitulatif (8.6) : le retirer et installer le profil choisi |
| Autre produit Click-to-Run sur un canal absent du dépôt | Par défaut : conservé tel quel, `NotApplicable` avec le motif « canal absent du dépôt » dans le rapport. Option dans le récapitulatif (8.6) : le retirer et installer le profil choisi |
| Même produit déjà installé, version plus ancienne que la source | Mise à jour depuis la source locale |
| Même produit, version égale ou plus récente | À jour |
| Langue installée absente de la source du canal | `NotApplicable`, motif « langue absente de la source » ; l'ODT n'est pas lancé |
| Office MSI ancien | Retiré par `<RemoveMSI />` lors de l'installation |

Mécanisme (R-08) :

- Mise à jour d'un Office existant : uniquement `setup.exe /configure` relancé, avec `<Add SourcePath="…" AllowCdnFallback="FALSE">`, les produits et les langues déjà installés. `OfficeC2RClient.exe` n'est pas utilisé (options non documentées, modification du registre du client). En cas d'échec, l'étape passe en erreur avec le code retour de l'ODT dans le rapport.
- Intégrité de la source avant l'ODT : avant tout `setup.exe /configure`, revérification du SHA-256 de tous les fichiers de la source utilisée, par rapport au manifeste. Au moindre écart, l'étape passe en erreur, l'ODT n'est pas lancé, et les fichiers fautifs sont listés dans le rapport. Mesuré en R-10 : hors ligne, l'ODT face à un fichier de source corrompu n'échoue pas, il attend le retour du réseau.
- Garde-fou de durée : `setup.exe` est arrêté au-delà de `client.odtTimeoutMinutes` (30 min par défaut, 6.1). L'étape passe alors en erreur avec le motif « délai dépassé », les journaux de l'ODT sont conservés, et Office est détecté de nouveau par la version de `WINWORD.EXE` (8.3).
- Retrait et installation : un seul XML avec `<Remove All="TRUE" />` et `<Add>`, validé sur runner.
- Langues : le contrôle de 8.3 se fait avant de lancer l'ODT. Mesuré sur runner : un Office installé en fr-fr et en-us mis à jour depuis une source fr-fr seule fait échouer l'ODT (code 17002), avec ou sans `Language ID="MatchInstalled"`, après qu'il a déjà mis à jour le client Click-to-Run.

Le XML d'installation est généré dans `C:\ProgramData\OffPatch\temp\` avec le chemin absolu de la source, puis supprimé dès la fin de l'étape. Pour un profil LTSC, une clé MAK peut être saisie dans un champ masqué. Elle reste en mémoire, est injectée dans le XML temporaire, et le journal indique seulement « clé fournie : oui ». Pour un profil en boîte, le rapport rappelle que l'activation se fait avec le compte Microsoft du client.

### 8.6 Mode automatique

Toutes les décisions sont prises avant le démarrage, sur un écran récapitulatif : étapes prévues, profil Office (avec le rappel, s'il y a lieu, que Microsoft ne prend pas ce profil en charge sur ce Windows, et la source), retrait d'un Office existant (jamais par défaut : un Office existant est conservé et mis à jour s'il est sur un canal du dépôt, son retrait est un choix explicite), clé éventuelle, forçage éventuel pour Windows 10. Je valide une seule fois, puis plus aucune question n'est posée.

Pendant la session :

- `C:\ProgramData\OffPatch\state.json` contient l'identifiant de session, l'état de chaque étape, le nombre de redémarrages, le numéro de série du volume du support et le chemin relatif de la racine.
- Avant un redémarrage : copie de `resume.ps1` dans ProgramData, création de la tâche planifiée `OffPatch-Reprise` (à l'ouverture de session de l'utilisateur courant, privilèges les plus élevés), compte à rebours de `rebootCountdownSeconds` avec bouton Annuler, puis redémarrage.
- À l'ouverture de session suivante, `resume.ps1` cherche le support sur tous les lecteurs (fichier `offpatch.root` et numéro de série du volume) et relance l'interface avec `-Resume`. Si le support est absent, une petite fenêtre demande de le rebrancher et vérifie toutes les 5 secondes.
- Garde-fous : au plus `maxAutoReboots` redémarrages. Une étape qui échoue deux fois est abandonnée et signalée, la session continue avec les suivantes.
- En fin de session : suppression de la tâche, de `resume.ps1` et de `temp\`, archivage de `state.json` dans les journaux, rétablissement de Windows Update, bilan à l'écran, rapport écrit.
- Pas d'ouverture de session automatique : je rouvre la session moi-même après chaque redémarrage.
- Si je ferme la fenêtre en cours de route, l'outil demande confirmation et conserve l'état. Un bouton « Reprendre la session interrompue » apparaît au lancement suivant.

### 8.7 Mode manuel

Le même plan est affiché avec une case à cocher par étape. « Installer la sélection » lance les étapes cochées dans l'ordre du plan. Quand une étape demande un redémarrage, un bandeau l'indique avec un bouton « Redémarrer maintenant ». Aucune tâche planifiée n'est créée : au lancement suivant, l'outil refait simplement la détection.

### 8.8 Rapport d'intervention

En fin de session, ou en cas d'abandon, un rapport HTML autonome et imprimable est écrit dans `rapports/AAAA-MM-JJ_NomPC_NumeroDeSerie.html` sur le support, avec une copie dans `C:\ProgramData\OffPatch\logs\`. Il contient :

- date et heures de début et de fin ;
- nom du PC, fabricant, modèle, numéro de série BIOS ;
- Windows avant et après (édition, version, build et UBR), statut ESU pour Windows 10 ;
- Defender : version des définitions installées (et de la plateforme), ou motif de non-application, avec le rappel que Defender se met à jour seul dès que le PC est connecté à Internet ;
- chaque étape avec son résultat, son code retour éventuel et sa durée ;
- Office installé (produit, version, canal, langues) et le mode d'activation attendu, avec la mention, s'il y a lieu, que Microsoft ne prend pas ce profil en charge sur ce Windows (et la source) ;
- erreurs et avertissements ;
- version de l'outil et date du dépôt utilisé.

Aucune clé de produit n'y figure.

## 9. Interface graphique

Fenêtre WPF unique. En-tête : nom et version de l'outil, date du dépôt, alerte si le dépôt est ancien. Trois onglets.

**Onglet « Ce PC »**

- Bandeau système : édition, version, build et UBR, architecture, statut ESU (Windows 10), Office détecté, espace libre, alimentation, fabricant, modèle, numéro de série.
- Tableau des étapes : étape, détail (KB ou version), état, case à cocher en mode manuel.
- Bloc Office : liste des profils dont la source est présente dans le dépôt, langues disponibles dans cette source, case « Retirer l'Office déjà présent », champ de clé masqué pour les profils LTSC.
- Boutons : « Installation automatique », « Installer la sélection », « Redémarrer maintenant » (visible si nécessaire), « Reprendre la session interrompue » (si un état existe).
- Barre de progression globale, étape en cours, dernières lignes du journal.

**Onglet « Dépôt »**

- Résumé : date de la dernière mise à jour, taille totale, alerte de fraîcheur.
- Cibles, sources Office et langues à cocher (enregistrées dans `settings.json`).
- Tableau du manifeste : cible, catégorie, KB ou version, date, taille, état de l'intégrité.
- Boutons : « Vérifier les nouveautés » (`-ListOnly`), « Mettre à jour le dépôt », « Purger », « Préparer un support… », « Annuler ».

**Onglet « Journal »**

- Journal en direct, filtre par niveau, boutons d'ouverture du dossier des journaux et du dossier des rapports.

Règles de comportement :

- Pendant un traitement, les boutons qui entreraient en conflit sont désactivés.
- Un téléchargement peut être annulé. Une étape DISM en cours ne peut pas l'être : le bouton est grisé, avec une infobulle qui l'explique.
- Contrôles WPF standard, présentation sobre, libellés en français, fenêtre redimensionnable et lisible en haute résolution.

## 10. Journalisation

- Face Dépôt : `logs/depot_AAAA-MM-JJ_HHMMSS.log` dans la racine de l'outil.
- Face Installation : `C:\ProgramData\OffPatch\logs\session_AAAA-MM-JJ_HHMMSS.log`, avec une copie à côté du rapport.
- Format d'une ligne : `2026-10-14 09:12:03 [INFO] message`. Niveaux : DEBUG, INFO, WARN, ERROR. Le niveau minimal est réglé dans `settings.json`.
- Les journaux propres à DISM et à l'ODT sont rangés dans un sous-dossier de la session.

## 11. Sécurité et intégrité

- Téléchargements limités aux domaines Microsoft autorisés.
- Authenticité vérifiée côté dépôt, en ligne, au téléchargement : `Status` = `Valid`, signataire de l'organisation Microsoft Corporation, chaîne jusqu'à une racine Microsoft ; un certificat expiré mais horodaté reste valide, sans contrôle de date d'expiration (7.1, R-10).
- SHA-256 calculé au téléchargement et stocké dans le manifeste, y compris pour chaque fichier d'une source Office. Côté client : revérification du SHA-256 seulement, sur les fichiers utilisés, juste avant l'étape ; toute la source Office avant `setup.exe /configure` (8.4, 8.5).
- Clé de produit : mémoire et XML temporaire uniquement.
- Aucune élévation persistante : la tâche planifiée disparaît en fin de session.
- Écriture atomique du manifeste et de `state.json`.

## 12. Tests

Tests unitaires Pester, avec des mocks pour DISM, `Start-Process`, le registre, `Get-CimInstance`, BITS et le réseau. Les jeux de données de test (manifestes, sorties DISM, clés de registre simulées) sont dans `tests/Fixtures/`.

Tests de planification (`tests/Unit/Planner/`) : chaque cas associe une fixture d'état du PC et une fixture de manifeste au plan attendu, étapes dans l'ordre avec leur état et leurs points de redémarrage :

| Cas | État du PC | Plan attendu (principe) |
|---|---|---|
| P1 | Windows 11 24H2, 26100.1742 | Cumulative du dépôt, redémarrage ; enablement package si l'UBR projeté atteint `minUbr`, sinon « Ignorée (prérequis) » |
| P2 | Windows 11 25H2, 26200.9457, cumulative d'octobre au dépôt | Cumulative d'octobre, redémarrage, puis enablement package (UBR projeté ≥ `minUbr`), redémarrage |
| P3 | Windows 11 25H2, 26200.9550 | Cumulative à jour si celle du dépôt n'est pas plus récente ; enablement package installable d'emblée (UBR réel ≥ `minUbr`), redémarrage |
| P4 | Windows 11 26H2 à jour | Aucune étape Windows ; enablement package non applicable |
| P5 | Windows 10 22H2 sans les SSU récents (UBR < 3271) | SSU autonome, puis cumulative, redémarrage |

Tests réels, selon deux moyens :

- **Runners GitHub hébergés** (dépôt privé, jetables), pour ce qu'ils couvrent : CI à chaque push (PSScriptAnalyzer et Pester sous Windows PowerShell 5.1), face Dépôt (recherche au catalogue, téléchargements, contrôles d'intégrité, `windows-2025`), Windows 11 ARM64 client sans redémarrage (`windows-11-arm`). Les workflows lourds se déclenchent à la main.
- **Interventions réelles** pour le reste : tout ce qui demande un redémarrage, Windows 11 x64 client, Windows 10, un support physique. On commence toujours par l'action `Plan`, en lecture seule, avant toute installation.

| Test | Situation de départ | Attendu | Où |
|---|---|---|---|
| T1 | Windows 11 26H2 x64 installé depuis une ISO, sans Office | Mode auto complet, Office Famille 2024 installé, rapport sans erreur | Intervention réelle (redémarrages, x64 client) |
| T2 | Windows 11 24H2 x64 avec un Office préinstallé | Enablement package appliqué, ancien Office retiré, profil LTSC 2024 installé avec une clé | Intervention réelle (redémarrages, x64 client) |
| T3 | Windows 11 25H2 x64 déjà à jour | Rien à installer, rapport cohérent | Runner `windows-11-arm` pour l'action `Plan` sur un 25H2 à jour (en ARM64), puis intervention réelle en x64 |
| T4 | Windows 10 22H2 x64 avec ESU actif | Cumulative ESU installée | Intervention réelle (Windows 10) |
| T5 | Windows 10 22H2 x64 sans ESU | Avertissement, aucune étape Windows en mode auto | Intervention réelle (Windows 10) |
| T6 | Windows 11 ARM64 | Mode manuel complet, Office 64 bits fonctionnel | Runner `windows-11-arm` pour les étapes sans redémarrage, puis matériel réel |
| T7 | Support débranché pendant un redémarrage | Fenêtre d'attente, reprise dès le rebranchement, même sur une autre lettre de lecteur | Intervention réelle (redémarrage, support physique) |
| T8 | Préparation d'un support en FAT32 | Refus avec message explicite | Runner `windows-2025` avec un disque virtuel formaté en FAT32, puis support réel |

Les résultats sont notés dans le journal de `TODO.md`.

## 13. Critères d'acceptation de la v1

- Mise à jour du dépôt en un clic, avec le résumé des nouveautés.
- Préparation d'un support filtré, sans perte des rapports déjà présents.
- Tests T1 à T8 réussis.
- Aucun gel de l'interface pendant les traitements longs.
- Journal et rapport produits pour chaque session, y compris en cas d'échec.
- PSScriptAnalyzer sans erreur, tests Pester au vert.
- README couvrant la mise en place, l'usage mensuel et le dépannage courant.

## 14. Évolutions envisagées après la v1

- Profil Microsoft 365 Apps (même mécanisme ODT, canal Current).
- Génération d'une ISO Windows à jour en intégrant la cumulative hors ligne.
- Outil de suppression de logiciels malveillants (MSRT).
- Signature des scripts avec un certificat de code.
- Paquet de préparation ESU Windows 10 (KB5126256 à ce jour) dans le dépôt. Écarté de la v1 : l'inscription à l'ESU demande de toute façon une connexion, et le paquet redémarre le PC de lui-même (R-04).

## 15. Historique

- 1.0 (4 octobre 2026) : version initiale.
- 1.1 (4 octobre 2026) : manifeste (7.2), `resultingBuild` remplacé par `baseBuilds` et `resultingUbr` ; détection de la cumulative Windows (8.3) adaptée en conséquence. Suite de R-01 : un même KB est publié pour 24H2, 25H2 et 26H2 avec la même UBR et des builds de base différentes.
- 1.2 (4 octobre 2026) : arborescence (5), dépôt `depot/files/<sha256>/<nom d'origine>`, un dossier par fichier, dédoublonné ; chemin d'exemple du manifeste (7.2) aligné ; purge par comptage de références (7.3) ; ajout de `tests/runner/` et `.github/workflows/`. Suite de R-02 : la checkpoint est jointe à chaque cumulative et DISM explore le dossier du paquet.
- 1.3 (4 octobre 2026) : distinction Windows 10 / 11 par `CurrentBuild`, libellé par `Win32_OperatingSystem.Caption` (8.2, 8.3) ; détection des cumulatives et des checkpoints par l'UBR, liste DISM réservée au diagnostic (8.3) ; enablement package 26H2 en élément épinglé, nouveau fichier `config/pinned-items.json` (3.2, 5, 6.4, 7.3), installé après la cumulative et son redémarrage si l'UBR atteint `minUbr` (8.3). Suite des mesures sur runner (R-02, R-09) et de R-03.
- 1.4 (4 octobre 2026) : règles de prérequis du planificateur (UBR projeté, revérification avant chaque étape, état `SkippedPrerequisite`, dépendances ignorées) (8.3) ; SSU autonome Windows 10 KB5031539 en élément épinglé, catégorie `windows-ssu`, champ `applyBelowUbr` (3.2, 6.4, 8.3) ; paquet .NET identique pour 24H2, 25H2 et 26H2 (8.3) ; tests de planification P1 à P5 (12) ; paquet de préparation ESU en évolution (14). Suite de R-04 et R-05.
- 1.5 (4 octobre 2026) : détection .NET par comparaison de la version du paquet lue dans le .msu avec la liste DISM, choix 4.8 / 4.8.1 sous Windows 10 par la valeur `Release` (8.3) ; lecture du .msu au téléchargement (7.1) ; champs `package` et `netRelease` du manifeste, contre-vérification de `resultingUbr` par le .msu, la valeur du .msu faisant foi en cas de divergence (7.2) ; section 12 : tests réels sur runners GitHub hébergés ou sur intervention réelle, matrice T1 à T8 avec le lieu de chaque test, à la place des VM Hyper-V. Suite de R-05.
- 1.6 (4 octobre 2026) : Defender, applicable si actif ou passif, non applicable avec motif (jamais en erreur) si désactivé ou si `Get-MpComputerStatus` échoue, contrôle de la version après exécution (8.3, 8.4) ; rapport d'intervention : version des définitions installées et rappel de la mise à jour automatique une fois le PC connecté (8.8). Suite de R-06.
- 1.7 (4 octobre 2026) : plateforme Defender (KB4052623) dans le périmètre, catégorie `defender-platform`, canal « Current Channel (Broad) » seul (3.2, 6.2, 7.1, 7.3), retirée des évolutions (14) ; deux types de dépendance, prérequis bloquant (`prerequisites`, conditions) et dépendance d'ordre (`runsAfter`), dans le manifeste et `pinned-items.json` (6.4, 7.2, 8.3) ; plateforme exécutée avant les définitions, attente bornée à 120 s avec avertissement (8.3, 8.4). Suite de R-06.
- 1.8 (4 octobre 2026) : tableau 3.3 : product IDs confirmés (mentions « à vérifier » levées), une seule source Current pour les quatre profils en boîte, colonne de prise en charge sous Windows 10 22H2 (aucun profil pris en charge, d'après les configurations requises Microsoft) ; champ `supportedOn` des profils (6.3) ; avertissement non bloquant en contrôle préalable (8.2), rappel dans l'écran récapitulatif (8.6) et dans le rapport (8.8). Suite de R-07.
- 1.9 (4 octobre 2026) : portée de `allowedDomains` précisée (téléchargements faits par OffPatch, pas le trafic propre de l'ODT) (6.1). Suite de R-07 et R-13.
- 1.10 (5 octobre 2026) : langues par source Office, Current en fr-fr + en-us, LTSC en fr-fr (6.1) ; comparaison des langues installées avec celles de la source avant de lancer l'ODT, `NotApplicable` « langue absente de la source » (8.3, 8.5) ; tableau 8.5 : autre produit Click-to-Run sur un canal du dépôt conservé et mis à jour par défaut ; mise à jour par `setup.exe /configure` seulement, échec en erreur avec le code retour, `OfficeC2RClient.exe` écarté ; retrait par `<Remove All="TRUE" />` + `<Add>` (8.5) ; retrait toujours explicite dans le récapitulatif (8.6). Suite de R-08.
- 1.11 (5 octobre 2026) : version d'Office installée lue sur `WINWORD.EXE` (repli `EXCEL.EXE`, puis `POWERPNT.EXE`) dans le dossier `InstallationPath`, `VersionToReport` en diagnostic, écart signalé et Office « À installer » (8.3) ; tableau 8.5 : option de retrait et d'installation du profil dans les deux cas d'autre produit Click-to-Run, canal absent du dépôt en `NotApplicable` « canal absent du dépôt ». Suite de R-08 et R-09.
- 1.12 (5 octobre 2026) : critères Authenticode au téléchargement (`Valid`, organisation Microsoft Corporation, racine Microsoft, certificat expiré mais horodaté accepté) et SHA-256 de chaque fichier d'une source Office (7.1, 11) ; côté client, SHA-256 seul, juste avant l'étape (8.4, 11) ; source Office entière revérifiée avant `setup.exe /configure`, étape en erreur et ODT non lancé au moindre écart ; garde-fou de 30 min sur l'ODT (`odtTimeoutMinutes`), « délai dépassé », nouvelle détection d'Office ; pas de délai sur DISM (6.1, 8.4, 8.5). Suite de R-10.
