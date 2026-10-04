# Points à vérifier

Chaque point est traité en phase 0, avant d'écrire le code qui en dépend. Sources prioritaires : learn.microsoft.com, support.microsoft.com, le Microsoft Update Catalog lui-même. Un forum peut donner une piste, jamais une conclusion.

Pour chaque point, remplir les quatre champs en dessous de la question. Les scripts d'essai vont dans `scratch/`, jamais dans `app/`. Les essais qui modifient le système passent par les workflows GitHub Actions (`tests/runner/`, `docs/essais/`).

## À valider sur intervention réelle

Ce que les runners GitHub ne permettent pas de vérifier (décision de David du 2026-10-04). On commence toujours par l'action `Plan`, en lecture seule, avant toute installation.

- Application effective d'une cumulative après redémarrage, build obtenue et nombre de redémarrages (R-02, R-03, R-14) : un runner ne redémarre pas.
- Mode automatique complet : reprise après redémarrage, tâche planifiée, `resume.ps1` (phase 5).
- Windows 11 x64 client : aucun runner standard (`windows-2025` est un Windows Server 2025).
- Windows 10 22H2 avec et sans ESU (R-04).
- Support d'installation sans checkpoint (24H2 antérieure à 26100.1742, R-02).

Statuts possibles : À vérifier, En cours, Tranché, Bloqué.

---

## R-01 Titres des cumulatives Windows dans le catalogue

Question : quels titres exacts le catalogue utilise-t-il pour la cumulative mensuelle de Windows 11 x64 et ARM64 depuis la sortie de la 26H2 ? Le même paquet est-il proposé pour 24H2, 25H2 et 26H2, et sous quel libellé ? Même question pour Windows 10 22H2 x64 en ESU. Quels mots-clés permettent d'écarter préversions, mises à jour dynamiques, hotpatchs et éditions Server ?

Impact : contenu de `catalog-queries.json`, sélection de la bonne cumulative.

- Statut : Tranché
- Sources (consultées le 2026-10-04) :
  - Microsoft Update Catalog, recherches `2026-09 Cumulative Update for Windows 11, version 24H2` (puis 25H2, 26H2, 26H1), `2026-09 Cumulative Update Windows 10 Version 22H2`, `2026-08 Cumulative Update for Windows 11, version 25H2`, `KB5129195`, `KB5129236`, `KB5120994`, `KB5089466`, `Hotpatch Windows 11 24H2`. Script : `scratch/r01-catalog-search.ps1`.
  - Microsoft Update Catalog, `DownloadDialog.aspx` pour les six entrées de KB5129195 (résolution des liens, aucun téléchargement). Script : `scratch/r01-download-links.ps1`.
  - https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information (mise à jour du 2026-09-30) : tableaux des builds par version, types B/D/OOB, calendrier hotpatch, note sur 26H1.
  - https://learn.microsoft.com/en-us/windows/release-health/release-information : Windows 10 22H2, OOB KB5129236 du 2026-09-14 (19045.7727) après la B KB5122878 du 2026-09-08 (19045.7725).
- Conclusion :
  - Titres relevés pour Windows 11 (forme constante d'août à septembre 2026) :
    `2026-09 Cumulative Update for Windows 11, version 24H2 for x64-based Systems (KB5129195) (26100.9457)`
    `2026-09 Cumulative Update for Windows 11, version 25H2 for arm64-based Systems (KB5129195) (26200.9457)`
    `2026-09 Cumulative Update for Windows 11, version 26H2 for x64-based Systems (KB5129195) (26300.9457)`
    Forme générale : `AAAA-MM Cumulative Update for Windows 11, version <VV>H<n> for <x64|arm64>-based Systems (KB<n>) (<build>.<UBR>)`.
  - Un même KB est publié sous une entrée distincte pour chaque version (24H2, 25H2, 26H2). Seule la build du titre change (26100, 26200, 26300), l'UBR est identique. Les six entrées de KB5129195 renvoient exactement les mêmes URL de fichiers : il n'y a qu'un paquet par architecture. La date affichée dépend de l'entrée (26H2 : 2026-09-29, date d'ajout de la version au catalogue ; 24H2 et 25H2 : 2026-09-14). La date ne sert donc pas à trier.
  - Chaque entrée renvoie deux fichiers .msu : `windows11.0-kb5129195-x64_<sha1>.msu` et `windows11.0-kb5043080-x64_<sha1>.msu` (KB5043080 = cumulative checkpoint). L'ordre des liens varie d'une entrée à l'autre. Suite traitée en R-02.
  - Un mois peut compter plusieurs cumulatives non préversion : septembre 2026 a la B (KB5124008, .9445, 08/09) puis un OOB (KB5129195, .9457, 14/09), tous deux classés « Security Updates ». La bonne cumulative est celle dont l'UBR est le plus élevé, pas celle du Patch Tuesday.
  - Titres à écarter, tous observés :
    préversions `Cumulative Update Preview for Windows 11…` (KB5124010) ;
    mises à jour dynamiques `Safe OS Dynamic Update` et `Setup Dynamic Update` ;
    .NET `Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version …` ;
    Windows Server `Cumulative Update for Microsoft server operating system version 24H2…` (ne contient pas « Windows 11 ») ;
    Windows 11 26H1 (build 28000, branche distincte réservée à certains appareils neufs, non proposée en mise à jour depuis 24H2/25H2 selon Microsoft) : `…Windows 11, version 26H1…` (KB5129194).
  - Hotpatchs : aucun résultat au catalogue, ni par mot-clé ni par numéro (KB5120994, KB5089466 tirés du calendrier hotpatch). Ils passent par Windows Autopatch. L'exclusion `Hotpatch` reste par précaution.
  - Windows 10 22H2 : `2026-09 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5122878)`. Différences avec Windows 11 : « Version » avec majuscule et sans virgule, `x64`/`x86`/`ARM64` en majuscules, **pas de build dans le titre**, aucune mention « ESU ». Le même KB existe aussi sous `Windows 10 Version 21H2` (produit « Windows 10 LTSB ») et pour x86 et ARM64, à écarter. Classification variable : l'OOB KB5129236 est en « Updates », la B KB5122878 en « Security Updates ». On ne filtre donc pas sur la classification.
- Décision :
  - Le catalogue renvoie au plus 25 résultats par page. La requête générique `2026-09 Cumulative Update for Windows 11, version` atteint ce plafond et perd des entrées (KB5124008 absent du résultat), alors que la requête limitée à une version en renvoie 8. On envoie donc une requête par version listée dans la configuration : `AAAA-MM Cumulative Update for Windows 11, version 24H2`, puis `25H2`, puis `26H2`, et pour Windows 10 `AAAA-MM Cumulative Update for Windows 10 Version 22H2` (14 résultats). Les requêtes portent toujours sur le mois courant et le mois précédent (janvier 2027 → `2027-01` et `2026-12`) ; les résultats sont fusionnés, filtrés, puis la sélection par UBR s'applique (décision de David du 2026-10-04). Si une page revient avec 25 lignes, l'outil le signale dans le journal (risque de troncature). Contrôle des motifs sur les titres réels : `scratch/r01-check-patterns.ps1`. Valeurs proposées pour `catalog-queries.json` (à poser au bilan de phase) :
    - `win11-x64` / `windows-lcu` : include `^\d{4}-\d{2} Cumulative Update for Windows 11, version (24H2|25H2|26H2) for x64-based Systems \(KB\d+\) \(\d+\.\d+\)$`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|26H1|arm64`.
    - `win11-arm64` / `windows-lcu` : même motif avec `arm64-based Systems`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|26H1|x64-based`.
    - `win10-x64` / `windows-lcu` : include `^\d{4}-\d{2} Cumulative Update for Windows 10 Version 22H2 for x64-based Systems \(KB\d+\)$`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|21H2|x86|ARM64`.
  - Règle de sélection Windows 11 (validée par David le 2026-10-04, à reporter au bilan de phase) : regrouper les entrées par KB, puis garder le KB dont l'UBR (dernier nombre du titre) est le plus élevé. Une seule copie des fichiers par architecture, quelle que soit la version du titre.
  - Règle de sélection Windows 10 (décision de David du 2026-10-04) : même règle, l'UBR étant tiré de la correspondance KB → build publiée sur https://learn.microsoft.com/en-us/windows/release-health/release-information (motif `19045.<UBR> KB<n>` dans le texte de la page, 88 KB relevés le 2026-10-04, KB5129236 → 19045.7727). Si aucun KB candidat n'y figure, tri par date de publication en secours, avec un avertissement dans le journal. Conséquence : `learn.microsoft.com` devra figurer dans `allowedDomains` (à reporter en R-13).
  - Vérifié par `scratch/r01-check-patterns.ps1` (2026-10-04, 0 échec) : passage d'année, correspondance Windows 10, KB5129236 passe le motif d'inclusion et est retenu pour septembre 2026, KB5129195 retenu pour Windows 11 x64 et ARM64 parmi les entrées de 2026-08 et 2026-09.
  - Cahier des charges passé en version 1.1 (accord de David du 2026-10-04) : `resultingBuild` remplacé par `baseBuilds` et `resultingUbr` (7.2), détection de la cumulative adaptée (8.3).
  - Le motif d'exemple du cahier des charges (6.2, `"search": "Cumulative Update Windows 11 x64"`) ramène aussi les préversions, les dynamiques et 26H1, et le catalogue limite une page à 25 résultats : il faut la requête datée ci-dessus et l'exclusion de 26H1. Simple exemple de format, pas de modification du cahier des charges nécessaire ; la règle de sélection « UBR le plus élevé » sera ajoutée au bilan de phase, avec ton accord.
  - Pistes notées pour d'autres points : nom de fichier contenant un SHA-1 (R-10), domaine de téléchargement `catalog.sf.dl.delivery.mp.microsoft.com` (R-13), taille affichée par entrée 4933,5 Mo pour Windows 11 x64 et 4770,5 Mo pour ARM64 (deux .msu, répartition par fichier inconnue), 895,9 Mo pour Windows 10 x64 (R-12).

## R-02 Cumulatives « checkpoint »

Question : sur une installation récente de Windows 11 24H2, 25H2 ou 26H2, quelles cumulatives checkpoint faut-il installer avant la dernière cumulative ? Comment DISM les traite-t-il quand tous les fichiers .msu sont dans un même dossier ? Quel ordre et combien de redémarrages ?

Impact : catégorie `windows-checkpoint`, ordre du plan, champ `prerequisites` du manifeste.

- Statut : En cours (documentation dépouillée, essai sur runner GitHub : `docs/essais/R-02-checkpoint.md`, workflow `r02-arm64.yml`)
- Sources (consultées le 2026-10-04) :
  - https://learn.microsoft.com/en-us/windows/deployment/update/catalog-checkpoint-cumulative-updates (« Checkpoint cumulative updates and Microsoft Update Catalog usage », mise à jour du 2025-01-31).
  - https://support.microsoft.com/help/5129195 (KB5129195), section « Microsoft Update Catalog » : tableau « Required checkpoint cumulative update » / « Target cumulative update », méthodes 1 et 2.
  - https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options : `/Add-Package` et paragraphe « Checkpoint cumulative updates ».
  - Microsoft Update Catalog : recherche `KB5043080`, `DownloadDialog.aspx` des entrées de KB5129195, requêtes HEAD sur les fichiers (`scratch/r02-download-pair.ps1 -ListOnly`).
  - https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information : 24H2 disponible le 2024-10-01 en 26100.1742, 26H2 disponible le 2026-09-29 en 26300.9457.
  - Machine de développement (lecture seule, sans élévation) : 26200.9550, `Get-HotFix`.
- Conclusion :
  - Une cumulative postérieure à une checkpoint ne s'applique qu'à un système qui a déjà cette checkpoint, ou une cumulative ultérieure. Microsoft annonce que d'autres checkpoints pourront suivre. Aujourd'hui, la seule pour 24H2/25H2/26H2 est KB5043080 (2024-09, 26100.1742). Son titre au catalogue a l'ancienne forme, sans virgule ni build : `2024-09 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5043080)`.
  - Le catalogue livre la checkpoint avec la cumulative : la fenêtre de téléchargement d'une entrée montre « all prior checkpoints » (Learn), et la page du KB distingue la checkpoint requise de la cible. Tailles relevées en HEAD : KB5043080 x64 533 761 740 octets, ARM64 610 638 429 ; KB5129195 x64 4 639 422 594, ARM64 4 391 570 921.
  - Deux méthodes documentées :
    - Méthode 1 : chaque .msu un par un, dans l'ordre (checkpoint puis cible), avec DISM ou wusa. Si la checkpoint est déjà présente, wusa indique qu'elle est déjà installée. Le code retour de DISM dans ce cas n'est pas documenté.
    - Méthode 2 : tous les .msu dans un même dossier, DISM appelé avec la cible comme seul `/PackagePath`. DISM explore le dossier, installe les checkpoints nécessaires, puis la cible. Contraintes : « Ensure no other files are present in the folder » (KB) ; « Only the target cumulative update and any prerequisite checkpoint cumulative updates should be in the -PackagePath folder » et « Cumulative update packages with a revision less than or equal to the target cumulative update will be processed » (DISM). Les sous-dossiers sont aussi explorés.
  - Conséquence pour le dépôt : DISM cherche les checkpoints dans le dossier du fichier passé en `/PackagePath`, même quand on lui donne un fichier. Avec la structure actuelle du cahier des charges (`win11-x64/lcu/` avec deux mois de rétention), une installation depuis le dépôt ferait aussi traiter la cumulative du mois précédent, dont la révision est inférieure à la cible. Un stockage par hash avec un fichier par dossier écarte ce risque.
  - Aucun document ne dit s'il faut redémarrer entre la checkpoint et la cible avec la méthode 1. Le nombre de redémarrages reste à mesurer.
  - Supports d'installation : une ISO 24H2 publique (26100.1742) contient déjà KB5043080, une ISO 26H2 actuelle (26300.9457) contient déjà KB5129195. Le cas « checkpoint manquante » ne concerne que des supports 24H2 antérieurs à la sortie publique (anciennes images constructeur, préversions). Sur une ISO récente, le cas courant est « checkpoint déjà présente ».
  - Détection : la machine de développement, en 26200.9550 (elle a donc forcément la checkpoint), n'affiche pas KB5043080 dans `Get-HotFix`, qui ne permet donc pas de détecter la checkpoint. La liste des paquets DISM demande l'élévation et n'a pas pu être lue ici. La forme du nom du paquet est relevée par `r02-arm64.yml`.
- Décision (provisoire, à confirmer par `r02-arm64.yml` puis sur intervention réelle) :
  - Prérequis : tout fichier d'une entrée du catalogue autre que celui du KB principal (repéré par `kb<numéro>` dans le nom du fichier) est un prérequis. Aucun numéro de checkpoint en dur. Ordre d'installation : prérequis d'abord, par numéro de KB croissant (à revoir si plusieurs checkpoints coexistent un jour), puis la cible.
  - Méthode recommandée : **installation séquentielle depuis le dépôt (méthode 1, DISM)**, un `/Add-Package` par fichier, en sautant les prérequis déjà détectés. Raisons : pas de copie de 5,2 Go sur `C:` (temps de copie depuis la clé, espace libre) ; compatible avec le dépôt dédoublonné et la rétention ; chaque étape est journalisée et reprise séparément ; méthode documentée par Microsoft. Condition : chaque fichier seul dans son dossier du dépôt, sinon DISM explore les autres .msu. Repli si les essais montrent un problème : méthode 2 avec un dossier de travail sous `C:\ProgramData\OffPatch\temp\` contenant uniquement la cible et ses prérequis (copie, et contrôle d'espace libre augmenté de la taille des fichiers).
  - Détection de la checkpoint : liste des paquets DISM, comme demandé par David. Complément proposé, à valider : la checkpoint est forcément présente si la build courante figure dans `baseBuilds` et que l'UBR courant est supérieur ou égal à celui de la checkpoint (1742 pour KB5043080), puisque les cumulatives sont cumulatives. Cet UBR n'est pas dans le titre de la checkpoint au catalogue (ancienne forme) : il viendrait de la page release-information, comme pour Windows 10 (R-01).
  - Code retour de DISM quand la checkpoint est déjà installée : relevé par la seconde passe de `r02-arm64.yml`, puis à reporter en R-14.
  - Stockage (décision de David du 2026-10-04, relecture de R-01) : KB5043080 étant joint à chaque entrée de cumulative Windows 11 (R-01), le stockage des fichiers est dédoublonné par hash et la purge se fait par comptage de références (un fichier n'est supprimé que si plus aucun élément du manifeste ne le référence).
  - Proposition de structure qui en découle, à valider avant de toucher au cahier des charges (section 5) : un dossier par fichier, nommé d'après son SHA-256, par exemple `depot/files/<sha256>/windows11.0-kb5129195-x64_….msu`, les éléments du manifeste pointant vers ces chemins.

## R-03 Enablement package 26H2

Question : numéro de KB, présence au catalogue pour x64 et ARM64, build minimale requise. Peut-il s'installer juste après la cumulative, avant le redémarrage ?

Impact : catégorie `windows-ekb`, regroupement des redémarrages.

- Statut : À vérifier
- Piste (notée le 2026-10-04 à la demande de David) : KB5121794 serait l'enablement package 26H2. Sa présence au catalogue est contradictoire selon les sources. Le 2026-10-04, aucun résultat au catalogue pour `KB5121794`, `Enablement Package 26H2`, `Enablement Package Windows 11` ni `Feature Update to Windows 11, version 26H2 via Enablement Package`. À vérifier : la page du KB sur support.microsoft.com et d'autres formulations de recherche. Autre indice : `Get-HotFix` sur la machine de développement (25H2) liste KB5054156, à identifier.
- Sources :
- Conclusion :
- Décision :

## R-04 Windows 10 22H2 et ESU

Question : les cumulatives ESU téléchargées depuis le catalogue s'installent-elles par DISM sur un PC inscrit à l'ESU grand public (prolongé jusqu'au 12 octobre 2027) ? Comment détecter cette inscription hors ligne (licence, registre, WMI) ? Même question pour l'ESU commercial, activé par clé MAK.

Impact : contrôle préalable Windows 10, comportement du mode auto.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-05 Cumulatives .NET Framework

Question : titres exacts au catalogue pour chaque cible, versions de .NET Framework concernées (3.5 et 4.8.1), méthode de détection d'une cumulative déjà installée.

Impact : catégorie `dotnet`, détection.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-06 Définitions Defender

Question : liens de téléchargement officiels de mpam-fe.exe pour x64 et ARM64, lecture de la version du fichier, comportement si un antivirus tiers est actif. Une mise à jour de la plateforme Defender est-elle nécessaire sur une installation récente pour que les définitions s'appliquent ?

Impact : catégorie `defender`, détection, éventuelle évolution vers la plateforme.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-07 ODT et sources Office

Question :

- product IDs exacts de `HomeStudent2021Retail`, `HomeBusiness2021Retail`, `Standard2024Volume`, `ProPlus2021Volume`, `Standard2021Volume` ;
- canal à utiliser pour les produits en boîte 2021 et 2024 ;
- comportement de l'Office 64 bits sur un PC ARM64 ;
- manière fiable de récupérer la dernière version de l'ODT ;
- structure du dossier source après `/download`, devenir des anciennes versions, rôle de `v64.cab`.

Impact : `profiles.json`, téléchargement et purge Office.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-08 Office déjà présent

Question : comment mettre à jour un Office Click-to-Run déjà installé à partir de la source locale (chemin de mise à jour temporaire et `OfficeC2RClient.exe`, ou autre méthode documentée) ? Comment retirer un Office préinstallé par le fabricant, souvent en plusieurs langues ? `<Remove All="TRUE" />` peut-il se combiner avec `<Add>` dans le même fichier ?

Impact : tableau 8.5 du cahier des charges.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-09 Détection des cumulatives installées

Question : quelle méthode est la plus fiable entre la comparaison build et UBR, la liste des paquets DISM et `Get-HotFix` ? Comment obtenir, au moment du téléchargement, la build résultante d'une cumulative (page d'historique des mises à jour, métadonnées du .msu) ?

Impact : champ `resultingBuild`, états `UpToDate` et `Pending`.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-10 Contrôle d'intégrité

Question : `Get-AuthenticodeSignature` sous PowerShell 5.1 donne-t-il un résultat exploitable sur les .msu, .cab et .exe concernés ? Le catalogue fournit-il un hash (dans le nom de fichier ou les métadonnées) ?

Impact : étape de vérification après téléchargement.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-11 MSCatalogLTS

Question : licence (redistribution dans `lib/`), version à figer, fonctionnement sous PowerShell 5.1 et sur ARM64. Plan B si le site du catalogue change de structure.

Impact : dépendance de la face Dépôt.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-12 Volumes

Question : taille réelle des fichiers par cible et par source Office. Un fichier dépasse-t-il 4 Go ? Quelle taille de support recommander ?

Impact : refus du FAT32, README.

- Statut : À vérifier
- Piste (2026-10-04, R-02) : KB5129195 x64 fait 4 639 422 594 octets (plus de 4 Gio), ARM64 4 391 570 921 octets. Un seul fichier dépasse donc la limite du FAT32.
- Sources :
- Conclusion :
- Décision :

## R-13 Domaines de téléchargement

Question : domaines réellement atteints après redirection pour le catalogue, mpam-fe.exe, l'ODT et le CDN Office.

Impact : `allowedDomains`.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-14 Moteur d'installation des paquets

Question : `dism.exe /Online /Add-Package` ou `Add-WindowsPackage -Online` ? Codes retour, gestion du 3010, emplacement des journaux, comportement avec un dossier contenant plusieurs .msu. Un outil tiers comme W10UI apporterait-il quelque chose de plus ?

Impact : exécuteur des étapes Windows.

- Statut : À vérifier
- Piste (2026-10-04, R-02) : codes retour de DISM pour un .msu déjà installé (checkpoint ou cumulative) et pour une cumulative dont la checkpoint manque, à mesurer avec `r02-arm64.yml` (`docs/essais/R-02-checkpoint.md`). Le cas « checkpoint manquante » n'est pas reproductible sur un runner (image récente) : à valider sur intervention réelle. DISM cherche les checkpoints dans le dossier du `/PackagePath` et explore les sous-dossiers.
- Sources :
- Conclusion :
- Décision :

## R-15 Suspendre Windows Update pendant une session

Question : quelle méthode documentée permet de suspendre Windows Update le temps de la session puis de le rétablir proprement, sans laisser de trace sur le PC du client ?

Impact : option `pauseWindowsUpdateDuringSession`.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :
