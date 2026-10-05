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
  - Échec de la recherche au catalogue sur `windows-11-arm` (premier run) : non reproduit par le passage croisé `catalog-cross` (https://github.com/Dano7762/offpatch/actions/runs/37200935234), 15 recherches sur 15 réussies (arm64 depuis `windows-2025`, x64 et arm64 depuis `windows-11-arm`). Ni cause réseau ni cause de filtre : incident passager du catalogue probable, couvert depuis par trois tentatives espacées dans `Save-CatalogEntryFile.ps1`.
  - Runner GitHub `windows-11-arm`, workflow `r02-arm64` (2026-10-04) : https://github.com/Dano7762/offpatch/actions/runs/37199152736 (relevés initiaux, recherche au catalogue en échec) et https://github.com/Dano7762/offpatch/actions/runs/37199356179 (essai complet ; seule la copie finale de `CBS.log` a échoué, fichier verrouillé, corrigé depuis).
- Résultats sur runner (Windows 11 Entreprise 25H2 ARM64, 26200.9457 au départ, 120 Go libres) :
  - Le runner avait déjà KB5129195 : l'essai mesure le cas « déjà installé », pas une installation. Relancer `r02-arm64.yml` après le Patch Tuesday du 13 octobre 2026 avec la nouvelle cumulative pour mesurer une vraie installation (prévu, décision de David).
  - `DISM /Online /Add-Package /NoRestart` sur la checkpoint déjà présente : code 0, « The operation completed successfully », 18 s puis 13 s. Sur la cumulative déjà présente : code 0, même message, 53 s. Aucun redémarrage mis en attente. **DISM ne distingue pas « installé » de « déjà présent »** : l'état doit être établi avant et après par la détection, pas par le code retour.
  - Liste DISM : la checkpoint apparaît comme `Package_for_RollupFix~31bf3856ad364e35~arm64~~26100.1742.1.10`, état **Staged** ; la cumulative comme `Package_for_RollupFix~31bf3856ad364e35~arm64~~26100.9457.1.0`, état **Installed**. Le numéro de version du paquet porte la build 26100 même sur une 25H2 (build courante 26200), puis l'UBR. Aucun numéro de KB dans le nom.
  - `Get-HotFix` liste KB5129195 mais pas KB5043080 (comme sur la machine de développement).
  - Téléchargement ARM64 : 4 391 570 921 et 610 638 429 octets, SHA-1 conformes, Authenticode `Valid`, un seul domaine (`catalog.sf.dl.delivery.mp.microsoft.com`).
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
  - Détection (décision de David du 2026-10-04, après les mesures sur runner ; cahier des charges 1.3, 8.3) : **la détection repose sur l'UBR**. Checkpoint présente si la build courante est 26100, 26200 ou 26300 et que l'UBR courant est supérieur ou égal à l'UBR de la checkpoint (1742 pour KB5043080). Cumulative à jour si l'UBR courant est supérieur ou égal à `resultingUbr`. La liste des paquets DISM ne sert qu'au diagnostic : le nom de paquet porte la build 26100 même sur une 25H2, et la checkpoint y apparaît à l'état « Staged ». L'UBR de la checkpoint n'est pas dans son titre au catalogue (ancienne forme) : il vient de la page release-information, comme pour Windows 10 (R-01).
  - Code retour de DISM quand la checkpoint est déjà installée : 0 (mesuré, voir ci-dessus). Reporté en R-14.
  - Reste à mesurer : une installation réelle (runner après le 13 octobre 2026), puis la build après redémarrage et le nombre de redémarrages (intervention réelle).
  - Stockage (décision de David du 2026-10-04, relecture de R-01) : KB5043080 étant joint à chaque entrée de cumulative Windows 11 (R-01), le stockage des fichiers est dédoublonné par hash et la purge se fait par comptage de références (un fichier n'est supprimé que si plus aucun élément du manifeste ne le référence).
  - Proposition de structure qui en découle, à valider avant de toucher au cahier des charges (section 5) : un dossier par fichier, nommé d'après son SHA-256, par exemple `depot/files/<sha256>/windows11.0-kb5129195-x64_….msu`, les éléments du manifeste pointant vers ces chemins.

## R-03 Enablement package 26H2

Question : numéro de KB, présence au catalogue pour x64 et ARM64, build minimale requise. Peut-il s'installer juste après la cumulative, avant le redémarrage ?

Impact : catégorie `windows-ekb`, regroupement des redémarrages.

- Statut : Tranché (décision de David du 2026-10-04 : élément épinglé)
- Sources (consultées le 2026-10-04) :
  - https://support.microsoft.com/help/5121794 : « KB5121794: Feature update to Windows 11, version 26H2 by using an enablement package ».
  - https://support.microsoft.com/help/5054156 : enablement package 25H2 (précédent, même situation au catalogue).
  - Microsoft Update Catalog, recherches sans résultat : `KB5121794`, `KB5054156`, `Enablement Package 26H2`, `Enablement Package Windows 11`, `Feature Update to Windows 11, version 26H2 via Enablement Package`, `Feature update to Windows 11, version 26H2`, `Windows 11, version 26H2 enablement`, `Windows 11 26H2 Upgrades`, `Feature Update to Windows 11, version 25H2 via Enablement Package`.
  - https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information : KB5124010 = 26100.9550 / 26200.9550 (2026-09-22).
  - Liens directs (pistes, pas des preuves) : https://pureinfotech.com/windows-11-26h2-enablement-package-download/ et https://actu.pcastuces.com/actu-42992-windows-11-26h2-les-liens-de-telechargement-direct-du-package-activation-kb5121794-sont-disponibles.htm donnent les deux mêmes liens. Les articles ElevenForum, Neowin et Techdows indiqués par David n'ont pas été retrouvés par la recherche (outil de recherche web indisponible, recherche Bing sans résultat sur ces sites).
  - Preuve : workflow `depot-x64` en mode liens directs, https://github.com/Dano7762/offpatch/actions/runs/37200937432 (runner `windows-2025`, PowerShell 5.1).
- Conclusion :
  - KB5121794 s'applique à 24H2 et 25H2 (Famille, Professionnel, Entreprise, Éducation, IoT Entreprise), un seul redémarrage. Il n'est pas indexé au catalogue (« This update is only available through the other release channels » sur la page du KB ; la 25H2 était dans le même cas). Les fichiers sont pourtant hébergés sur le domaine de fichiers du catalogue :
    - x64 : `https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/94520a88-858f-4832-a57d-7211f6d84a4e/public/Windows11.0-KB5121794-x64_5e20a3cce48d6611b16bdec42b07167f5456586a.msu`, 177 535 octets ;
    - ARM64 : `https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9d8dc3d0-9cbf-4eb1-9411-722e3e6a19b3/public/Windows11.0-KB5121794-arm64_77a76caf2d362bb293a4d18058388f2717365abe.msu`, 178 969 octets.
  - Vérification sur runner : pour les deux fichiers, SHA-1 identique à l'empreinte du nom, `Get-AuthenticodeSignature` = `Valid`, type `Authenticode`, signataire `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`, aucun autre domaine traversé. En-tête `Last-Modified` des fichiers : 27 août 2026 (avant la sortie publique du 29 septembre).
  - Prérequis : la page du KB exige « September 22, 2026—KB5124010 (OS Builds 26100.9546) Preview or a later cumulative update ». La page release-information donne 9550 pour KB5124010 ; on retient **9550**, valeur de release-information (décision de David), la plus exigeante. La cumulative de sécurité de septembre (KB5129195, 9457) ne suffit pas : en septembre, l'étape est ignorée faute d'UBR suffisant ; à partir de la cumulative du 13 octobre 2026, elle devient possible.
  - Installation juste après la cumulative, avant le redémarrage : pas retenue. L'UBR exigé n'est atteint qu'après le redémarrage qui suit la cumulative.
- Décision (David, 2026-10-04) :
  - Nouveau mécanisme d'**élément épinglé** : `config/pinned-items.json` (créé avec les deux entrées ci-dessus : `appliesToBaseBuilds` 26100 et 26200, `minUbr` 9550, `resultingBuild` 26300). Téléchargé une fois, vérifié (domaine, SHA-1, Authenticode Microsoft), jamais purgé ; lien mis à jour à la main une fois par an. Pas de recherche au catalogue pour cette catégorie. Cohérence du fichier contrôlée par `tests/Unit/PinnedItems.Tests.ps1`.
  - Planificateur : l'enablement package n'est installé que si l'UBR du PC est supérieur ou égal à `minUbr`, après la cumulative et son redémarrage, puis redémarrage.
  - Écarté de l'outil : UUP dump (intermédiaire tiers). Officiels mais non retenus : API Windows Update Agent (`Microsoft.Update.Session`) et WSUS.
  - Cahier des charges 1.3 : sections 3.2, 5, 6.4, 7.3 et 8.3.
  - Reste à valider sur intervention réelle : installation effective, passage en 26300 après redémarrage. Le domaine `catalog.sf.dl.delivery.mp.microsoft.com` est déjà relevé en R-13.

## R-04 Windows 10 22H2 et ESU

Question : les cumulatives ESU téléchargées depuis le catalogue s'installent-elles par DISM sur un PC inscrit à l'ESU grand public (prolongé jusqu'au 12 octobre 2027) ? Comment détecter cette inscription hors ligne (licence, registre, WMI) ? Même question pour l'ESU commercial, activé par clé MAK.

Impact : contrôle préalable Windows 10, comportement du mode auto.

- Statut : Bloqué (documentation dépouillée ; deux points ne peuvent se trancher que sur un vrai PC Windows 10, aucun runner GitHub ne fournissant Windows 10 client. Relevé en lecture seule prêt : `docs/essais/R-04-esu.md`)
- Sources (consultées le 2026-10-04) :
  - https://learn.microsoft.com/en-us/windows/whats-new/extended-security-updates (mise à jour du 2025-11-17) : programme ESU, Windows 10 22H2 seulement.
  - https://learn.microsoft.com/en-us/windows/whats-new/enable-extended-security-updates (mise à jour du 2026-04-22) : activation de l'ESU entreprise par MAK, identifiants d'activation, vérification par `slmgr.vbs /dlv`, activation par téléphone.
  - https://support.microsoft.com/en-us/windows/windows-10-consumer-extended-security-updates-esu-program-33e17de9-36b3-43bb-874d-6c53d2e4bf42 : ESU grand public.
  - https://support.microsoft.com/help/5122878 et https://support.microsoft.com/help/5129236 : cumulatives Windows 10 de septembre 2026.
  - https://support.microsoft.com/help/5126256 et https://support.microsoft.com/help/5072653 : paquets de préparation ESU.
  - Microsoft Update Catalog : recherches `KB5072653`, `KB5126256`.
  - Machine de développement (lecture seule) : requête WMI sur `SoftwareLicensingProduct`.
- Conclusion :
  - **ESU entreprise** : clé MAK installée par `slmgr.vbs /ipk`, puis activation par `slmgr.vbs /ato <identifiant>` (en ligne) ou par téléphone (`/dti` puis `/atp`). Identifiants d'activation documentés, « the same across all eligible Windows ESU editions and all devices » : année 1 `f520e45e-7413-4a34-a497-d2765967d094`, année 2 `1043add5-23b1-4afb-9a0f-64343c8f3f8d`, année 3 `83d49986-add3-41d7-ba33-87c7bfb5c0fb`. La vérification documentée est `slmgr.vbs /dlv`, qui affiche le nom du programme ESU et « License Status: Licensed ». `slmgr` lit la classe WMI `SoftwareLicensingProduct` : la requête équivalente, en lecture seule et hors ligne, filtre sur ces trois `ID` et lit `LicenseStatus` (1 = Licensed). Requête validée sur la machine de développement : 0,6 s, aucun résultat sur Windows 11, comme attendu. Les LTSB/LTSC ne sont pas couvertes par l'ESU Windows 10.
  - **ESU grand public** : inscription par Paramètres > Windows Update avec un compte Microsoft administrateur, jusqu'au 12 octobre 2027. Exclus : PC joints à un domaine AD ou à Microsoft Entra, ou inscrits à une solution MDM (« Entra registered » reste admis), et PC qui ont déjà une licence ESU. La seule vérification documentée est l'écran Paramètres > Windows Update. **Aucune méthode hors ligne n'est documentée** (ni WMI, ni registre). La mention « Devices that already have an ESU license » suggère que l'inscription produit une licence, mais rien ne le confirme.
  - **Paquet de préparation** : obligatoire pour l'inscription, après une cumulative du 14 octobre 2025 ou plus récente (KB5066791). Le plus récent est KB5126256 (2026-09), qui remplace les précédents dont KB5072653 (« Each ESU Licensing Preparation Package supersedes any previously released licensing package »). Il « does not enroll the device or install Windows 10 security updates » et redémarre le PC automatiquement. Il est au catalogue : `2026-09 Extended Security Updates (ESU) Licensing Preparation Package for Windows 10 Version 22H2 for x64-based Systems (KB5126256)`, 814 Ko. Le motif d'inclusion des cumulatives (R-01) ne le capture pas.
  - **Installation depuis le catalogue** : les pages KB des cumulatives Windows 10 de septembre (« Applies to: Windows 10 ESU ») citent le Microsoft Update Catalog comme canal, avec le paquet autonome. Prérequis documentés pour une image ancienne : SSU autonome KB5005260 si le PC n'a pas la cumulative KB5003173 (mai 2021) ou plus récente ; SSU KB5031539 si l'image n'a pas KB5028244 (juillet 2023) ou plus récente. **Aucune page ne dit si l'installation par DISM vérifie la licence ESU**, ni ce qui se passe sur un PC non inscrit.
- Décision (provisoire, compatible avec le cahier des charges 8.2, sans modification) :
  - Statut ESU d'un PC Windows 10 (19045) calculé en lecture seule par WMI :
    - « Actif (entreprise, année N) » si l'un des trois identifiants a `LicenseStatus = 1` ;
    - « Indétectable » sinon, ce qui couvre l'ESU grand public tant que le relevé sur un vrai PC n'a pas montré de trace exploitable. Conformément au cahier des charges (8.2), cela donne un avertissement, et en mode auto l'étape Windows est ignorée sauf si David la force dans le récapitulatif.
  - Les trois identifiants d'activation iront dans la configuration (`config/settings.json`, au bilan de phase), pas dans le code.
  - Build 19044 (LTSC 2021) : hors cible, pas d'ESU Windows 10 ; seule la 19045 est acceptée.
  - Paquet de préparation KB5126256 : **hors v1** (décision de David du 2026-10-04 : l'inscription à l'ESU exige une connexion et le paquet redémarre seul). Noté en évolution, section 14 du cahier des charges.
  - SSU autonomes des images anciennes (décision de David du 2026-10-04 : les embarquer en éléments épinglés, avec détection et passage avant la cumulative, pas d'avertissement seul) :
    - **KB5031539** (SSU 19041.3562, octobre 2023), nécessaire si le PC n'a pas KB5028244 = 19045.3271 (release-information, 2023-07-25). Titre au catalogue : `2023-10 Servicing Stack Update for Windows 10 Version 22H2 for x64-based Systems (KB5031539)`. Lien résolu par la fenêtre de téléchargement du catalogue : `https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/10/ssu-19041.3562-x64_de23c91f483b2e609cec3e4a995639d13205f867.msu`, 16 140 380 octets (ARM64 : `ssu-19041.3562-arm64_2c72074f5308183392636cfc693b834a27f99446.msu`, 14 885 696 octets). Vérifié sur runner (workflow `depot-x64`, https://github.com/Dano7762/offpatch/actions/runs/37202749032) : SHA-1 identique au nom, Authenticode `Valid`, signataire Microsoft Corporation, un seul domaine. Ajouté à `config/pinned-items.json` (x64 seulement, cible `win10-x64`) : `appliesToBaseBuilds` 19045, `applyBelowUbr` 3271. Le nom de fichier ne porte pas de numéro de KB.
    - **KB5005260** (SSU d'août 2021) : **non embarqué** (retrait validé par David le 2026-10-04), sans objet pour la 22H2. Il n'est requis que si le PC n'a pas KB5003173 = 19041/19042/19043.985 (mai 2021) ; or la plus petite build 19045 publiée dans release-information est 19045.2130 (sortie de la 22H2 le 2022-10-18), donc tout PC 22H2 a déjà un UBR supérieur à 985. Le catalogue ne le publie d'ailleurs que pour Windows 10 2004, 20H2 et 21H1, pas pour la 22H2.
    - À valider sur intervention réelle : besoin ou non de redémarrer après le SSU, code retour d'une réinstallation.
- À valider sur intervention réelle (`docs/essais/R-04-esu.md`) :
  1. Trace lisible hors ligne d'une inscription ESU grand public (produit de licence, identifiant, état).
  2. Confirmation de la détection entreprise sur un PC avec MAK ESU.
  3. Plus tard, avec l'accord de David : installation par DISM d'une cumulative ESU sur un PC inscrit et sur un PC non inscrit (tests T4 et T5).

## R-05 Cumulatives .NET Framework

Question : titres exacts au catalogue pour chaque cible, versions de .NET Framework concernées (3.5 et 4.8.1), méthode de détection d'une cumulative déjà installée.

Impact : catégorie `dotnet`, détection.

- Statut : Tranché (décision de David du 2026-10-04 ; cahier des charges 1.5, 7.1, 7.2 et 8.3)
- Sources (consultées le 2026-10-04) :
  - https://support.microsoft.com/help/5126052 : « Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2, Windows 11, version 25H2 and Microsoft server operating system 24H2 ». Prérequis : « you must have .NET Framework 3.5 or 4.8.1 installed ». Redémarrage : « if any affected files are being used ».
  - https://support.microsoft.com/help/5126046 : article chapeau Windows 10 21H2/22H2 (3.5 et 4.8), qui renvoie aux articles par produit, dont KB5126146 « Cumulative Update for .NET Framework 3.5, 4.8 and 4.8.1 for Windows 10 Version 22H2 ». Les pages KB5126146 et KB5126421 renvoient une erreur.
  - https://learn.microsoft.com/en-us/dotnet/framework/install/how-to-determine-which-versions-are-installed : valeur `Release` de `HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full` ; 4.8 = 528040 / 528372 / 528049 selon le système, 4.8.1 = 533320 / 533325 ; tester « greater than or equal ».
  - Microsoft Update Catalog : recherches par mois et par version (`scratch/r05-patterns.ps1`), fenêtres de téléchargement de KB5126052, KB5126046, KB5126146, KB5126421.
  - Workflow `msu-inspect` (https://github.com/Dano7762/offpatch/actions/runs/37203060768) : contenu des .msu et paquets installés sur `windows-2025` (Server 2025, 26100.33438) et `windows-11-arm` (25H2, 26200.9457).
- Conclusion :
  - **Windows 11** (24H2, 25H2, 26H2) : une seule cumulative .NET par mois, pour 3.5 et 4.8.1. Titre : `2026-09 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5126052)` (`for arm64` en ARM64). Les entrées 24H2, 25H2 et 26H2 du même KB renvoient **le même fichier** par architecture (`windows11.0-kb5126052-x64-ndp481_<sha1>.msu`, `…-arm64-ndp481_<sha1>.msu`) : la cumulative .NET ne dépend pas de l'enablement package (cahier des charges 1.4, 8.3). La page du KB ne cite pas 26H2, mais le catalogue publie l'entrée 26H2 avec le même fichier. Pas de build dans le titre.
  - **Windows 10 22H2** : trois entrées par mois. `…for .NET Framework 3.5 and 4.8 for Windows 10 Version 22H2 for x64 (KB5126046)` (fichier `windows10.0-kb5126046-x64-ndp48_<sha1>.msu`, 81 842 924 octets), `…3.5 and 4.8.1… (KB5126421)` (`windows10.0-kb5126421-x64-ndp481_<sha1>.msu`, 81 247 370 octets) et `…3.5, 4.8 and 4.8.1… (KB5126146)`, qui renvoie **les deux fichiers précédents**. Le bon fichier dépend de la version de .NET 4.x installée : 4.8 (Release 528040 à 533319) ou 4.8.1 (Release ≥ 533320). Fichiers servis par `catalog.s.download.windowsupdate.com`. Les titres sans architecture sont les versions x86 ; une entrée ARM64 du catalogue porte un libellé incohérent (`3.5 and 4.8` pour KB5126146), sans effet sur la cible `win10-x64`.
  - Motifs vérifiés sur août et septembre 2026 (une entrée retenue par mois et par cible) :
    - `win11-x64` : include `^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5 and 4\.8\.1 for Windows 11, version (24H2|25H2|26H2) for x64 \(KB\d+\)$`, exclude `Preview|Server|26H1` ;
    - `win11-arm64` : idem avec `for arm64` ;
    - `win10-x64` : include `^\d{4}-\d{2} Cumulative Update for \.NET Framework 3\.5, 4\.8 and 4\.8\.1 for Windows 10 Version 22H2 for x64 \(KB\d+\)$` (entrée qui apporte les deux fichiers), exclude `Preview|Server|21H2|ARM64`.
  - **Identité du paquet** : chaque .msu .NET contient un .cab dont le fichier `update.mum` donne le nom et la version du paquet, lisibles avec `expand.exe`, présent sur tout Windows. KB5126052 : `Package_for_DotNetRollup_481` 10.0.9347.1 (x64 et ARM64) ; KB5126046 : `Package_for_DotNetRollup` 10.0.4806.2 ; KB5126421 : `Package_for_DotNetRollup_481` 10.0.9346.1. Sur les deux runners à jour, `dism /Get-Packages` liste exactement `Package_for_DotNetRollup_481~31bf3856ad364e35~<arch>~~10.0.9347.1`, état `Installed` : **la version lue dans le .msu se retrouve à l'identique dans la liste DISM**.
  - `Get-HotFix` liste KB5126052 sur les deux runners. Mais une cumulative .NET plus récente installée par Windows Update ferait disparaître le KB du dépôt de cette liste : la présence du KB ne suffit pas pour dire « à jour ».
  - Release .NET 4 relevée sur les runners : 533509, valeur absente du tableau Learn mais supérieure à 533320 (4.8.1) ; d'où la règle « supérieur ou égal ».
  - .NET 3.5 est une fonctionnalité à la demande (`Microsoft-Windows-NetFx3-OnDemand-Package`) ; la cumulative la met à jour si elle est présente.
- Décision (validée par David le 2026-10-04) :
  - Au téléchargement, l'outil lit dans chaque .msu .NET le nom et la version du paquet (`update.mum`, via `expand.exe`) et les inscrit dans le manifeste.
  - Sur le PC : à jour si la liste DISM contient un paquet de même nom, état `Installed`, de version supérieure ou égale ; à installer sinon. `Get-HotFix` reste un complément de diagnostic.
  - Windows 10 : choix du fichier selon la valeur `Release` (≥ 533320 → fichier `ndp481`, sinon `ndp48`).
  - Sélection mensuelle : pas de build dans le titre ; on retient l'entrée la plus récente parmi les non-préversions du mois courant et du précédent. En cas d'égalité, la version de paquet la plus élevée.
  - Cumulative Windows 10 (décision de David, voir R-09) : release-information reste la source de sélection ; la lecture du .msu sert de contre-vérification.
  - Reste à valider sur intervention réelle : Windows 10 (choix ndp48 ou ndp481, liste DISM après installation, nom du KB dans `Get-HotFix`) et code retour quand la cumulative .NET est déjà présente (R-14).

## R-06 Définitions Defender

Question : liens de téléchargement officiels de mpam-fe.exe pour x64 et ARM64, lecture de la version du fichier, comportement si un antivirus tiers est actif. Une mise à jour de la plateforme Defender est-elle nécessaire sur une installation récente pour que les définitions s'appliquent ?

Impact : catégorie `defender`, détection, éventuelle évolution vers la plateforme.

- Statut : Tranché (plateforme très ancienne à confirmer sur intervention réelle)
- Sources (consultées le 2026-10-04) :
  - https://www.microsoft.com/en-us/wdsi/defenderupdates (« Latest security intelligence updates for Microsoft Defender Antivirus and other Microsoft antimalware »), lue dans le navigateur intégré : la page refuse les requêtes automatiques (HTTP 403 avec curl).
  - https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-updates (mise à jour du 2026-05-14) : définitions (KB2267602), plateforme mensuelle (KB4052623), support N-2 de la plateforme et du moteur.
  - https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-compatibility (mise à jour du 2026-08-21) : modes actif, passif, désactivé.
  - Machine de développement : en-têtes des liens (suivi des redirections), téléchargement de mpam-fe.exe x64 (autorisé par CLAUDE.md, cible la plus légère), lecture de la version et de la signature, sans exécution.
  - https://learn.microsoft.com/en-us/defender-endpoint/msda-updates-previous-versions-technical-upgrade-support : versions de plateforme et de moteur hors support N-2.
  - Microsoft Update Catalog, recherche `KB4052623` : `Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.26080.4) - Current Channel (Broad)`.
  - Workflow `r06-defender`, essai complet demandé par David (suppression des définitions, plateforme, définitions) : https://github.com/Dano7762/offpatch/actions/runs/37234923903.
  - Workflow `r06-defender`, essai avec mise à jour de plateforme : https://github.com/Dano7762/offpatch/actions/runs/37231644513.
  - Workflow `r06-defender` sur runners jetables : https://github.com/Dano7762/offpatch/actions/runs/37229995374, https://github.com/Dano7762/offpatch/actions/runs/37230374976, https://github.com/Dano7762/offpatch/actions/runs/37230720333, https://github.com/Dano7762/offpatch/actions/runs/37231034932.
- Conclusion :
  - **Liens officiels** (ligne « Microsoft Defender Antivirus for Windows 11, Windows 10, Windows 8.1, and Windows Server ») : `https://go.microsoft.com/fwlink/?LinkID=121721&arch=x64` et `https://go.microsoft.com/fwlink/?LinkID=121721&arch=arm64`. Ils redirigent vers `definitionupdates.microsoft.com/packages?arch=…`, puis vers `/packages/content/mpam-fe.exe?packageType=Signatures&packageVersion=1.459.553.0&arch=amd64&engineVersion=1.1.26080.3`. **La version figure dans l'URL de redirection avant tout téléchargement**, ce qui permet de savoir si le dépôt est à jour sans retélécharger 212 Mo. Tailles relevées le 2026-10-04 : 222 853 576 octets (x64), 222 341 064 octets (ARM64).
  - **Version du fichier** : `(Get-Item mpam-fe.exe).VersionInfo.FileVersion` = `1.459.553.0`, identique à la version des définitions publiée sur la page Microsoft et à la valeur `AntivirusSignatureVersion` de `Get-MpComputerStatus` après application. Description `AntiMalware Definition Update`. Signature Authenticode `Valid`, Microsoft Corporation, sous PowerShell 5.1.
  - **Antivirus tiers** : sur un poste non inscrit à Defender for Endpoint, Defender passe automatiquement en « Disabled mode » quand un antivirus tiers est installé ; il ne reçoit alors pas les définitions. En mode passif (poste inscrit à Defender for Endpoint), les définitions s'appliquent. `Get-MpComputerStatus`, valeur `AMRunningMode` : `Normal`, `Passive Mode` ou `EDR Block Mode` quand Defender est en service ; « Not running » relevé sur runner quand le service est arrêté. Sur un poste client, `root/SecurityCenter2`, classe `AntiVirusProduct`, liste les antivirus enregistrés (relevé : « Windows Defender » seul sur le runner client ; classe vide sur Windows Server).
  - **État des runners** (relevé au début de l'essai, à la demande de David) : sur `windows-11-arm`, `AMRunningMode` = `Normal`, `RealTimeProtectionEnabled` = `True`, seul antivirus enregistré « Windows Defender ». Defender y est donc pleinement actif, temps réel compris : les mesures valent pour un poste client ordinaire. Le runner `windows-2025` (serveur) n'a servi qu'aux premiers essais, non retenus.
  - **Plateforme** : sur Windows 11 25H2 ARM64, après `MpCmdRun -ResetPlatform` (retour à la plateforme de l'image, 4.18.25080.5, au lieu de 4.18.26080.4), les définitions du jour (1.459.553.0, moteur 1.1.26080.3) s'appliquent sans mise à jour de plateforme. Le moteur est fourni par mpam-fe.exe. La documentation ne garantit rien au-delà : « Platform and engine versions older than N-2 are no longer supported », seule la montée depuis la version livrée avec Windows (« upgrades from the Windows 10 release version ») restant prise en charge. Aucune page ne dit que des définitions récentes s'appliquent sur une plateforme ancienne (image constructeur de plus d'un an).
  - **Mise à jour de plateforme KB4052623** : une entrée au catalogue par version mensuelle (« Current Channel (Broad) », version dans le titre), qui contient un exécutable par architecture servi par `catalog.s.download.windowsupdate.com` : `updateplatform.amd64fre_<sha1>.exe` (39 243 776 octets), `updateplatform.arm64fre_<sha1>.exe` (39 128 696 octets), et x86. Essai sur runner ARM64 (https://github.com/Dano7762/offpatch/actions/runs/37231644513) : plateforme de l'image 4.18.25080.5, `updateplatform.arm64fre_….exe` lancé sans argument, code 0 en 27 s, plateforme passée en 4.18.26080.4, **aucun redémarrage en attente**, Defender de nouveau `Normal` en 15 s, puis `mpam-fe.exe -q` sans incident. `FileVersion` du fichier = version de la plateforme ; SHA-1 conforme au nom ; Authenticode `Valid`, signataire `CN=Microsoft Windows Publisher`. Une note Learn demande d'installer d'abord la version 4.18.2001.10 quand on part d'une plateforme plus ancienne qu'elle (premières versions de Windows 10, hors cible).
  - **Essai complet** (https://github.com/Dano7762/offpatch/actions/runs/37234923903, runner ARM64, temps réel actif) : `MpCmdRun -ResetPlatform` puis `-RemoveDefinitions -All` (codes 0) ; Defender arrêté juste après, sans définitions ; retour en mode `Normal` en 10 s, sur les définitions d'origine de l'image (1.459.384.0) et la plateforme de l'image (4.18.25080.5) ; plateforme KB4052623 en 35 s, code 0, aucun redémarrage en attente, Defender de nouveau `Normal` en 5 s, plateforme 4.18.26080.4 ; `mpam-fe.exe -q` en 16 s, code 0, **définitions passées de 1.459.384.0 à 1.459.553.0**. L'enchaînement plateforme puis définitions est vérifié de bout en bout, et l'attente bornée à 120 s est largement suffisante.
  - **Lancement** : la page Microsoft dit seulement « Simply launch the file » ; aucune option n'est documentée. Mesuré sur runner : `mpam-fe.exe -q` renvoie 0 en 19 s et applique les définitions ; sans argument, il renvoie 0 en 3 s quand les définitions sont déjà à jour. Dans les deux cas, aucune fenêtre ne bloque le runner.
  - **Pièges mesurés** : juste après un changement de plateforme, Defender est arrêté une quinzaine de secondes, et un lancement à ce moment-là échoue avec `0x800705B4` (délai dépassé) au bout d'environ 185 s, définitions inchangées. Sur Windows Server, avec le service arrêté, mpam-fe.exe renvoie 0 sans rien appliquer. **Le code retour ne prouve pas le succès.**
- Décision (compatible avec le cahier des charges 8.3, sans modification) :
  - Dépôt : un mpam-fe.exe par architecture, téléchargé par le lien officiel, version relevée dans l'URL de redirection pour éviter un téléchargement inutile, puis contrôlée par `FileVersion` et la signature Authenticode après téléchargement. Les liens restent dans la configuration.
  - Détection (décision de David du 2026-10-04, cahier des charges 1.6, 8.3) : applicable si `AMRunningMode` indique un Defender actif (`Normal`) ou passif (`Passive Mode`, `EDR Block Mode`). Defender désactivé ou `Get-MpComputerStatus` en échec : non applicable avec motif, **jamais en erreur**. Sinon, à jour si `AntivirusSignatureVersion` ≥ version du fichier ; à installer sinon. `SecurityCenter2` sert à nommer l'antivirus tiers dans le motif.
  - Exécution : `mpam-fe.exe -q`, après avoir vérifié que Defender est en service. L'étape n'est réussie que si `AntivirusSignatureVersion` atteint la version du fichier ; sinon, une seconde tentative après 30 s, puis « Erreur » avec le code retour.
  - Rapport (décision de David, cahier des charges 1.6, 8.8) : version des définitions installées et de la plateforme, ou motif de non-application, avec le rappel que Defender se met à jour seul dès que le PC est connecté.
  - **Plateforme Defender (KB4052623)**, décision de David du 2026-10-04 (cahier des charges 1.7) :
    - catégorie `defender-platform`, recherche mensuelle au catalogue, un fichier par architecture, seule la dernière version conservée ;
    - motif d'inclusion `^Update for Microsoft Defender Antivirus antimalware platform - KB4052623 \(Version 4\.18\.\d+\.\d+\) - Current Channel \(Broad\)$`, exclusion `Preview|Staged|Beta`. Vérifié le 2026-10-04 : seule l'entrée « Current Channel (Broad) » 4.18.26080.4 est retenue, l'ancienne 4.18.2001.10 est écartée. Le catalogue ne publiait ce jour-là aucune variante Preview, Staged ou Beta : l'exclusion n'a pas pu être éprouvée sur un titre réel ;
    - détection : à installer si `AMProductVersion` < version du fichier, mêmes règles d'applicabilité que les définitions ;
    - **dépendance d'ordre** des définitions (`runsAfter`), pas un prérequis bloquant : si la plateforme échoue, les définitions sont tentées quand même ;
    - exécution sans argument, sans redémarrage (mesuré), puis attente du retour de Defender en mode `Normal`, bornée à 120 s, avec un avertissement dans le journal en cas de dépassement.
  - À valider sur intervention réelle : application des définitions sur une plateforme très ancienne (Windows 10 22H2 ou 24H2 installé depuis une ISO ancienne).

## R-07 ODT et sources Office

Question :

- product IDs exacts de `HomeStudent2021Retail`, `HomeBusiness2021Retail`, `Standard2024Volume`, `ProPlus2021Volume`, `Standard2021Volume` ;
- canal à utiliser pour les produits en boîte 2021 et 2024 ;
- comportement de l'Office 64 bits sur un PC ARM64 ;
- manière fiable de récupérer la dernière version de l'ODT ;
- structure du dossier source après `/download`, devenir des anciennes versions, rôle de `v64.cab`.

Impact : `profiles.json`, téléchargement et purge Office.

- Statut : Tranché (essais sur runner demandés par David le 2026-10-04)
- Sources (consultées le 2026-10-04) :
  - https://learn.microsoft.com/en-us/troubleshoot/microsoft-365-apps/office-suite-issues/product-ids-supported-office-deployment-click-to-run (mise à jour du 2025-11-07) : liste des product IDs.
  - https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options (mise à jour du 2026-09-28) : attributs `Channel`, `OfficeClientEdition`, `SourcePath`, `AllowCdnFallback`, note sur Arm.
  - https://learn.microsoft.com/en-us/office/ltsc/2024/deploy (2026-08-10), https://learn.microsoft.com/en-us/office/ltsc/2021/deploy (2026-01-22), https://learn.microsoft.com/en-us/office/ltsc/2024/update, https://learn.microsoft.com/en-us/office/ltsc/2021/update, https://learn.microsoft.com/en-us/office/ltsc/2024/overview.
  - https://learn.microsoft.com/en-us/officeupdates/update-history-office-2024, https://learn.microsoft.com/en-us/officeupdates/update-history-office-2021, https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft365-apps-by-date.
  - https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/overview-office-deployment-tool (2026-07-19), https://learn.microsoft.com/en-us/officeupdates/odt-release-history (2026-09-09).
  - https://www.microsoft.com/en-us/download/details.aspx?id=49117 (Centre de téléchargement, ODT) : lu avec `Invoke-WebRequest` sous PowerShell 5.1 (HTTP 200) et dans le navigateur intégré ; curl reçoit une page de blocage.
  - https://support.microsoft.com/en-us/office/system-requirements/office-suites-for-individuals-and-families et https://support.microsoft.com/en-us/office/system-requirements/office-suites-for-enterprise-business-education-and-government : configurations requises, lues dans le navigateur intégré.
  - Workflow `r07-office` sur `windows-2025` (Office LTSC 2024 ProPlus, fr-fr, version 16.0.17932.20976 puis dernière version) : https://github.com/Dano7762/offpatch/actions/runs/37235902323 (une première tentative, https://github.com/Dano7762/offpatch/actions/runs/37235634040, a planté au relevé sur un dossier vide ; corrigé).
  - Workflow `r07-install` sur `windows-11-arm` (Home2024Retail, Current, fr-fr ; version 16.0.20430.20092 puis dernière version, purge, installation hors ligne) : https://github.com/Dano7762/offpatch/actions/runs/37236240851.
- Conclusion :
  - **Product IDs** : les cinq figurent dans la liste officielle de l'ODT, à l'identique : `HomeStudent2021Retail`, `HomeBusiness2021Retail`, `Standard2024Volume`, `ProPlus2021Volume`, `Standard2021Volume` (comme `Home2024Retail`, `HomeBusiness2024Retail` et `ProPlus2024Volume`, déjà confirmés). Les mentions « à vérifier » du tableau 3.3 du cahier des charges peuvent être levées.
  - **Canal des versions en boîte 2021 et 2024** : `Current`. L'ODT documente que, sans Office installé, le canal par défaut est `Current`, et que les versions sous licence en volume utilisent `PerpetualVL2024` ou `PerpetualVL2021` (« the only update channel available » pour LTSC). Les pages d'historique des mises à jour confirment : les « Retail versions of Office 2024 » et « of Office 2021 » sont en version 2609, build 20430.20118 au 30 septembre 2026, soit exactement la dernière build du Current Channel de Microsoft 365 Apps ; Office LTSC 2024 est en 2408, build 17932.21000. Une seule source `current` sert donc aux quatre profils en boîte.
  - **ARM64** : « Arm-based devices require Windows 11 or later… The 32-bit version… isn't supported on these devices. When you install the 64-bit version on an Arm-based device, it automatically includes the Arm-optimized components ». Office LTSC 2024 : « For Arm-based devices, Windows 11 is the minimum supported version ». Le choix du cahier des charges (64 bits partout) est confirmé ; une même source 64 bits sert x64 et ARM64. La note Arm de l'ODT parle de Microsoft 365 Apps ; pour Office 2021/2024 en boîte, aucune page ne le précise : l'installation sur ARM64 relève du test T6.
  - **Prise en charge sous Windows 10 22H2** (configurations requises de Microsoft, consultées le 2026-10-04) : Office 2024 et Office 2021 en boîte (Home & Student, Home & Business, Professional) : « Operating system: Windows 11 » seulement ; Office LTSC 2024 : Windows 11, Windows 11 LTSC 2024, Windows 10 LTSC 2021, Windows 10 LTSC 2019, Windows Server 2025, Windows Server 2022 ; Office LTSC 2021 : la même liste plus Windows Server 2019. **Aucun des huit profils n'est pris en charge sur Windows 10 22H2.** Écart à noter : la vue d'ensemble Learn d'Office LTSC 2021 (mise à jour du 2026-01-22) dit encore « supported on devices running Windows 10 or Windows 11 » ; la page des configurations requises, plus précise, fait foi.
  - **Dernière version de l'ODT** : l'historique Learn publie chaque version (16.0.20326.20112 du 9 septembre 2026, avec la version de `setup.exe`). Le fichier se récupère par la page officielle du Centre de téléchargement (`details.aspx?id=49117`), qui contient le lien direct `https://download.microsoft.com/download/<guid>/officedeploymenttool_<build>.exe` (aujourd'hui `officedeploymenttool_20326-20112.exe`, 3 522 096 octets). Le nom du fichier porte la version : l'outil peut comparer avec l'ODT déjà présent dans `tools/odt/` sans retélécharger. Microsoft recommande d'utiliser toujours la dernière version (« Always download and use the latest version of the ODT »). Les options d'extraction silencieuse (`/quiet /extract:`) ne sont pas documentées sur ces pages : elles seront vérifiées par l'essai sur runner.
  - **Structure de la source, `v64.cab`, anciennes versions** (non documentées ; mesurées sur runner, https://github.com/Dano7762/offpatch/actions/runs/37235902323) :
    - ODT : `officedeploymenttool_20326-20112.exe`, 3 522 096 octets, Authenticode `Valid` (Microsoft Corporation) ; extraction silencieuse `/quiet /extract:<dossier>` : code 0, `setup.exe` 16.0.20326.20112.
    - `setup.exe /download` crée `<SourcePath>\Office\Data\` avec un dossier par version (`16.0.17932.20976\`, 13 fichiers), un `v64_<version>.cab` par version et un `v64.cab`. Chaque cab contient `v64.hash` (empreinte puis numéro de version) et `VersionDescriptor.xml` (`<Available Build="…">`).
    - Un second `/download` dans le même dossier **ajoute** la nouvelle version et **conserve l'ancienne** : deux dossiers `16.0.17932.20976` et `16.0.17932.21000`, 7 096 Mo au total. `v64.cab` désigne alors la dernière (16.0.17932.21000), identique à `v64_16.0.17932.21000.cab`.
    - Durées : 90 s puis 62 s ; codes retour 0.
    - **Règle de purge déduite** : lire la version désignée par `v64.cab` (`v64.hash`, ligne 2), conserver ce dossier de version et son `v64_<version>.cab`, supprimer les autres dossiers de version et leurs `v64_<version>.cab`. Validée par le workflow `r07-install` (ci-dessous), avec un complément.
  - **Essai d'installation hors ligne** (https://github.com/Dano7762/offpatch/actions/runs/37236240851, runner Windows 11 ARM64) :
    - Source Current fr-fr pour Home2024Retail : 16.0.20430.20092 (3 914 Mo) puis dernière version 16.0.20430.20140, soit 7 518 Mo avant purge ; après purge, une seule version, celle de `v64.cab`, 3 605 Mo.
    - **Complément à la règle** : après un `/download` avec l'attribut `Version`, l'ODT n'écrit pas de `v64.cab`, seulement `v64_<version>.cab`. Si `v64.cab` est absent, la purge garde la version la plus élevée et ne supprime rien d'autre tant qu'un `/download` sans `Version` n'a pas produit `v64.cab`.
    - Domaines du CDN Office (`officecdn.microsoft.com`, `f.c2r.ts.cdn.office.net`) bloqués dans le fichier hosts pendant l'installation : `setup.exe /configure` avec `AllowCdnFallback="FALSE"` renvoie 0 en 234 s. **L'installation hors ligne depuis la source purgée fonctionne.**
    - Résultat : `HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration` : `VersionToReport` 16.0.20430.20140, `ProductReleaseIds` Home2024Retail, `Platform` x64, canal `CDNBaseUrl` http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60 (Current Channel). WINWORD.EXE, EXCEL.EXE et POWERPNT.EXE 16.0.20430.20140 portent un en-tête PE x64. **Non concluant** sur la nature native ou émulée (relecture de David du 2026-10-04) : les binaires ARM64EC portent eux aussi un en-tête x64, la lecture de l'en-tête PE ne distingue donc pas ARM64EC d'un x64 émulé. Sans impact sur l'outil, qui installe la même source 64 bits.
    - Une version en boîte 2024 s'installe donc sur Windows 11 ARM64 à partir de la source 64 bits (activation non testée : elle passe par le compte Microsoft du client).
- Essai d'origine : workflow `r07-office.yml`, script `tests/runner/Invoke-R07OfficeSourceTest.ps1`, sur `windows-2025`. Il récupère l'ODT par la page officielle (signature, extraction), télécharge une version ancienne de la source (par exemple Office LTSC 2024 16.0.17932.20976 du 8 septembre 2026), puis la dernière dans le même dossier. Il relève la structure, le contenu de `v64.cab` après chaque passage et les domaines cités dans les journaux de l'ODT. Volume estimé : quelques gigaoctets par passage pour une langue.
- Décision (provisoire) :
  - `profiles.json` : product IDs confirmés ; canal `Current` pour les quatre profils en boîte, `PerpetualVL2024` et `PerpetualVL2021` pour les LTSC ; `OfficeClientEdition="64"` partout.
  - ODT : récupération par la page officielle du Centre de téléchargement ; version lue dans le nom du fichier et dans `setup.exe`, comparée à l'historique Learn ; extraction `/quiet /extract:`.
  - Purge Office (cahier des charges 7.3) : conserver la version désignée par `v64.cab` (`v64.hash`, ligne 2) avec son `v64_<version>.cab`, supprimer les autres versions ; si `v64.cab` est absent, garder la version la plus élevée.
  - Installation : `AllowCdnFallback="FALSE"` validé hors ligne ; la version installée se lit dans `VersionToReport` (détection, cahier des charges 8.3).
  - Windows 10 (décision de David du 2026-10-04, cahier des charges 1.8, 3.3, 6.3, 8.2, 8.6, 8.8) : pour chaque profil non pris en charge, avertissement non bloquant en contrôle préalable, rappel dans l'écran récapitulatif et dans le rapport, avec la source ; champ `supportedOn` dans `profiles.json`. Les huit product IDs sont confirmés (mentions « à vérifier » levées) et une seule source Current sert les quatre profils en boîte.

## R-08 Office déjà présent

Question : comment mettre à jour un Office Click-to-Run déjà installé à partir de la source locale (chemin de mise à jour temporaire et `OfficeC2RClient.exe`, ou autre méthode documentée) ? Comment retirer un Office préinstallé par le fabricant, souvent en plusieurs langues ? `<Remove All="TRUE" />` peut-il se combiner avec `<Add>` dans le même fichier ?

Impact : tableau 8.5 du cahier des charges.

- Statut : Tranché (décisions de David du 2026-10-05 ; cahier des charges 1.10)
- Sources (consultées le 2026-10-04) :
  - https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options (mise à jour du 2026-09-28) : élément `Remove` (« If set to TRUE, all Microsoft 365 Apps products and languages are removed, including Project and Visio » ; sans attribut de langue, toutes les langues installées du produit sont retirées), élément `Updates` (`UpdatePath` local, réseau ou HTTP ; `TargetVersion`).
  - https://support.microsoft.com/en-us/topic/how-to-revert-to-an-earlier-version-of-office-2bd5c457-a917-d57e-35a1-f709e3dda841 : changement de version d'un Office Click-to-Run (Microsoft 365, Office 2024, Office 2021) par `setup.exe /configure` avec `<Updates Enabled="TRUE" TargetVersion="…" />`.
  - Aucune page officielle trouvée pour les options de `OfficeC2RClient.exe /update` (`displaylevel`, `forceappshutdown`, `updatepromptuser`) : elles ont été mesurées, pas documentées.
  - Workflow `r08-office` sur `windows-11-arm`, un runner neuf par scénario, source Current fr-fr (Home2024Retail) téléchargée par l'ODT 16.0.20326.20112, CDN Office bloqué dans le fichier hosts pour toute opération « hors ligne » : https://github.com/Dano7762/offpatch/actions/runs/37237307356.
  - Compléments demandés par David (langues, Office bilingue, taille des sources) : https://github.com/Dano7762/offpatch/actions/runs/37282900605 (RemoveAdd, MultiLangPlain, MultiLangMatch, SourceSize) et https://github.com/Dano7762/offpatch/actions/runs/37295343850 (MultiLangPlain avec relevé des fichiers, du service et du démarrage de Word).
  - Même page de l'ODT, élément `Language` : `MatchInstalled` « can't install … if the ODT can't find the correct language pack in the local source files » ; Microsoft recommande alors un `Fallback` et `AllowCdnFallback`.
- Conclusion (mesures sur runner) :
  - **Office « constructeur » retiré et remplacé en une passe** (scénario RemoveAdd) : O365HomePremRetail fr-fr + en-us installé depuis le CDN (16.0.20430.20140), puis, CDN bloqué, un seul XML avec `<Remove All="TRUE" />` et `<Add>` Home2024Retail depuis la source locale (`AllowCdnFallback="FALSE"`) : code 0, 120 s ; `ProductReleaseIds` passe de `O365HomePremRetail` à `Home2024Retail`. **`<Remove All="TRUE" />` se combine avec `<Add>` dans le même fichier.** Le passage en deux temps n'a pas été nécessaire.
  - **Mise à jour hors ligne par `setup.exe /configure` relancé** (UpdateConfigure) : Home2024Retail installé en 16.0.20430.20092 depuis la source locale, puis, CDN bloqué, `/configure` avec la même `<Add SourcePath=… AllowCdnFallback="FALSE">` sur une source qui contient la version récente : code 0, 192 s, version 16.0.20430.20140.
  - **Mise à jour hors ligne par `OfficeC2RClient.exe`** (UpdateC2RClient) : même départ ; valeur `UpdateUrl` de `HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration` mise temporairement sur la source locale, puis `OfficeC2RClient.exe /update user displaylevel=false forceappshutdown=true updatepromptuser=false` : rend la main en 4 s (code 0), la mise à jour se termine en arrière-plan, version 16.0.20430.20140 atteinte au bout de 105 s ; `UpdateUrl` restauré (absent au départ, supprimé à la fin).
  - **La source Current met à jour un O365HomePremRetail existant** (hypothèse de David vérifiée) : O365HomePremRetail 16.0.20430.20092 installé depuis le CDN, puis, CDN bloqué, mise à jour vers 16.0.20430.20140 depuis la source Current fr-fr **téléchargée pour Home2024Retail**, aussi bien par `/configure` (`<Add>` avec le produit O365HomePremRetail, 193 s) que par `OfficeC2RClient` (106 s). La source d'un canal et d'une langue n'est donc pas propre à un produit.
  - **Applications du Store** : Microsoft.MicrosoftOfficeHub (19.2506.56051.0) inchangée dans les cinq scénarios, retrait compris. Click-to-Run installe lui-même deux paquets MSIX qui lui sont liés (`Microsoft.OfficePushNotificationUtility`, `Microsoft.Office.ActionsServer`, à la version d'Office) ; après une mise à jour, les deux versions restent listées par `Get-AppxPackage -AllUsers`. L'outil ne les touche pas.
  - Durées : installation depuis le CDN 280 à 305 s ; installation ou mise à jour depuis la source locale 120 à 280 s.
  - **a. Retrait des langues** (37282900605, RemoveAdd) : le registre Click-to-Run (clés de langue sous `HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\ProductReleaseIDs`) déclare avant le remplacement `O365HomePremRetail.16:en-us` et `O365HomePremRetail.16:fr-fr`, après `Home2024Retail.16:fr-fr` seul. **Le retrait de en-us est confirmé.** Les dossiers de langue de `root\Office16` (1025, 1031, 1033, 1036, 1043, 3082) existent dans tous les cas : ce ne sont pas des indicateurs de langue installée.
  - **b. Office bilingue mis à jour depuis une source fr-fr seule** (Home2024Retail 16.0.20430.20092 fr-fr + en-us installé depuis le CDN, puis CDN bloqué, `/configure` avec `AllowCdnFallback="FALSE"`) : **échec, code 17002 (0x426A)** en 10 à 11 s, avec `<Language ID="fr-fr" />` (MultiLangPlain) comme avec `<Language ID="MatchInstalled" />` (MultiLangMatch). Les deux langues restent déclarées. Journal de l'ODT : Click-to-Run met d'abord à jour son propre client depuis la source locale (« ClientupdateTaskClientupdate », succès), puis le scénario INSTALL échoue (« Failure event set », « Exit with error code 17002 »).
  - **État après l'échec 17002** (37295343850) : `WINWORD.EXE` reste en 16.0.20430.20092 (applications non mises à jour), `OfficeClickToRun.exe` passe en 16.0.20430.20140, et **`VersionToReport` annonce 16.0.20430.20140, ce qui est faux pour les applications**. Office reste utilisable : service `ClickToRunSvc` en marche, Word se lance (toujours actif après 20 s). D'où la règle retenue : comparer les langues **avant** de lancer l'ODT, pour ne jamais laisser le PC dans cet état mixte.
  - **c. Taille des sources Current** (SourceSize) : fr-fr seule 3 604,5 Mo ; fr-fr + en-us 3 954,6 Mo, soit +350 Mo (`stream.x64.en-us.dat`, 349,8 Mo). Plus gros fichier `stream.x64.x-none.dat`, 2 781,9 Mo. La source 64 bits contient aussi `stream.x64.x-none.arm64x.dat` (454,3 Mo), indice que les composants Arm évoqués par Microsoft viennent de cette même source.
- Décision (David, 2026-10-05 ; cahier des charges 1.10, 6.1, 8.3, 8.5, 8.6) :
  - **Mise à jour d'un Office existant : `setup.exe /configure` seulement**, avec `<Add SourcePath=<source> AllowCdnFallback="FALSE">`, les produits et les langues déjà installés. En cas d'échec, étape en erreur avec le code retour dans le rapport.
  - **Option non retenue : `OfficeC2RClient.exe /update`** avec `UpdateUrl` temporaire. Elle fonctionne sur runner (105 s), mais ses options ne sont pas documentées et elle modifie le registre du client.
  - Office préinstallé à retirer : un seul XML `<Remove All="TRUE" />` + `<Add>`, validé. Le retrait reste un choix explicite dans le récapitulatif du mode auto ; par défaut, un autre produit Click-to-Run sur un canal présent dans le dépôt est **conservé et mis à jour** depuis la source locale.
  - **Langues** : avant de lancer l'ODT, comparaison des langues déclarées dans le registre Click-to-Run avec celles de la source du canal ; s'il en manque une, `NotApplicable` avec le motif « langue absente de la source », et l'ODT n'est pas lancé.
  - Langues par source (6.1) : Current = fr-fr + en-us (+350 Mo), LTSC 2024 et 2021 = fr-fr.
  - Piste pour la détection Office (8.3) : après un échec, `VersionToReport` peut annoncer une version que les applications n'ont pas. La version de `WINWORD.EXE` (ou d'une application du produit) est un contrôle plus sûr, à proposer à David avec R-09.

## R-09 Détection des cumulatives installées

Question : quelle méthode est la plus fiable entre la comparaison build et UBR, la liste des paquets DISM et `Get-HotFix` ? Comment obtenir, au moment du téléchargement, la build résultante d'une cumulative (page d'historique des mises à jour, métadonnées du .msu) ?

Impact : champ `resultingBuild`, états `UpToDate` et `Pending`.

- Statut : Tranché
- Pistes (2026-10-04, runner `windows-11-arm`, https://github.com/Dano7762/offpatch/actions/runs/37199152736) :
  - Sur Windows 11 25H2, la valeur de registre `ProductName` (`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`) vaut « Windows 10 Enterprise ». C'est un comportement connu de Windows 11, pas une anomalie du runner.
  - Règle (décision de David du 2026-10-04, cahier des charges 1.3, 8.2 et 8.3) : Windows 10 et Windows 11 se distinguent par `CurrentBuild` (22000 et plus = Windows 11), jamais par `ProductName`. Le libellé affiché vient de `Win32_OperatingSystem.Caption`. Mis en œuvre dans `app/module/OffPatch/Private/Get-OpWindowsIdentity.ps1`, test Pester `tests/Unit/Get-OpWindowsIdentity.Tests.ps1` (registre simulé « Windows 10 Pro » + build 26200 → Windows 11).
  - Règle de détection des cumulatives (même décision) : par l'UBR (voir R-02), la liste DISM et `Get-HotFix` ne servant qu'au diagnostic.
  - La liste DISM nomme les cumulatives `Package_for_RollupFix~…~26100.<UBR>.*`, sans numéro de KB, avec la build 26100 même sur 25H2 (voir R-02).
  - `Get-HotFix` voit la cumulative courante mais pas la checkpoint.
  - Cumulative Windows 10 (décision de David du 2026-10-04, cahier des charges 1.5, 7.2) : la page release-information reste la source de la sélection, l'UBR étant connu avant le téléchargement. Après téléchargement, la version du paquet lue dans le .msu (`update.mum`, comme pour .NET en R-05) contre-vérifie `resultingUbr` ; en cas de divergence, avertissement dans le journal, et la valeur du .msu fait foi pour la détection. Reste à vérifier sur runner la forme de cette version pour une cumulative Windows 10 (le paquet .NET donne `10.0.9347.1`).
- Sources (2026-10-04 et 2026-10-05) :
  - Runners `windows-11-arm` : https://github.com/Dano7762/offpatch/actions/runs/37199152736 et https://github.com/Dano7762/offpatch/actions/runs/37199356179 (liste DISM, `Get-HotFix`, registre).
  - Workflow `msu-inspect` sur `windows-2025` (2026-10-05) : https://github.com/Dano7762/offpatch/actions/runs/37296744436, ouverture de `windows10.0-kb5129236-x64_4413bfb0ab8a665cd0244ed67ec361170bb12ecb.msu` (lien résolu par la fenêtre de téléchargement du catalogue) et de `windows11.0-kb5129195-x64_….msu`.
  - https://learn.microsoft.com/en-us/windows/release-health/release-information : KB5129236 = 19045.7727.
  - R-01, R-02, R-05 et R-08 pour les éléments déjà établis.
- Conclusion :
  - **Méthode la plus fiable pour les cumulatives Windows : build et UBR** (`CurrentBuild` et `UBR` de `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`). Les cumulatives sont cumulatives : un UBR supérieur ou égal à celui de la cumulative du dépôt signifie qu'elle est couverte, y compris par une cumulative plus récente installée par Windows Update. La liste DISM (`Package_for_RollupFix~…~<build de branche>.<UBR>.*`, sans KB, checkpoint à l'état « Staged ») et `Get-HotFix` (qui ne voit pas la checkpoint et ne liste que le dernier KB) ne servent qu'au diagnostic.
  - **Build résultante au téléchargement** :
    - Windows 11 : UBR lu dans le titre du catalogue (`… (KB5129195) (26100.9457)`, R-01). Le .msu d'une cumulative Windows 11 24H2 ou plus récente n'est pas lisible par `expand.exe` (aucun contenu listé) : pas de contre-vérification par le .msu, le titre fait foi.
    - Windows 10 : UBR tiré de la page release-information avant le téléchargement (R-01), puis contre-vérifié par le .msu : le .cab principal contient `update.mum` avec `Package_for_RollupFix` en **19041.7727.1.0** pour KB5129236, soit l'UBR 7727 attendu (19045.7727). La version porte la build de branche 19041 ; l'UBR est le troisième nombre. Le .msu embarque aussi le SSU du mois (`SSU-19041.7714-x64.cab`, `Package_for_ServicingStack_7714` 19041.7714.1.3), ce qui n'enlève rien au besoin du SSU autonome KB5031539 sur les images antérieures à KB5028244 (R-04).
  - Famille Windows 10 / 11 par `CurrentBuild`, jamais par `ProductName` (« Windows 10 Enterprise » sur un Windows 11 25H2).
  - **Office (constat de R-08)** : après un échec de l'ODT (17002), `VersionToReport` peut annoncer une version que les applications n'ont pas (16.0.20430.20140 annoncé, `WINWORD.EXE` resté en 16.0.20430.20092), parce que le client Click-to-Run s'est mis à jour seul.
- Décision :
  - Cumulatives Windows : détection par build et UBR, conformément au cahier des charges 8.3 (`baseBuilds`, `resultingUbr`) ; aucune modification nécessaire.
  - Contre-vérification Windows 10 : lire `Package_for_RollupFix` dans `update.mum` et comparer son troisième nombre à `resultingUbr` ; en cas de divergence, avertissement et la valeur du .msu fait foi (cahier des charges 7.2). Pas de contre-vérification pour Windows 11.
  - **Office** (décision de David du 2026-10-05, cahier des charges 1.11, 8.3) : version installée = version de fichier de `WINWORD.EXE`, à défaut `EXCEL.EXE`, puis `POWERPNT.EXE`, dans le dossier `InstallationPath` du registre Click-to-Run ; `VersionToReport` en diagnostic seulement ; un écart entre les deux est signalé et rend Office « À installer ».

## R-10 Contrôle d'intégrité

Question : `Get-AuthenticodeSignature` sous PowerShell 5.1 donne-t-il un résultat exploitable sur les .msu, .cab et .exe concernés ? Le catalogue fournit-il un hash (dans le nom de fichier ou les métadonnées) ?

Impact : étape de vérification après téléchargement.

- Statut : Tranché (décisions de David du 2026-10-05 ; cahier des charges 1.12)
- Piste ARM64 (2026-10-04, workflow `r02-arm64`, https://github.com/Dano7762/offpatch/actions/runs/37199356179) : mêmes résultats pour les deux .msu ARM64 (`Valid`, SHA-1 conforme au nom).
- Piste (2026-10-04, workflow `depot-x64`, https://github.com/Dano7762/offpatch/actions/runs/37199155132, runner `windows-2025`, Windows PowerShell 5.1.26100) : pour les deux .msu de KB5129195 x64, `Get-AuthenticodeSignature` renvoie `Valid`, type `Authenticode`, signataire `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`. Le SHA-1 calculé est égal à l'empreinte de 40 caractères en fin de nom de fichier (`windows11.0-kb5129195-x64_<sha1>.msu`). Reste à voir : .cab, mpam-fe.exe, machine sans accès réseau (vérification de révocation), ARM64.
- Sources (2026-10-05) :
  - https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature?view=powershell-5.1 : un fichier signé à la fois par catalogue Windows et par signature intégrée est jugé sur la signature de catalogue ; aucune précision sur le contenu de l'état `Valid`.
  - Workflow `r10-integrity` sur `windows-11-arm`, scénarios Signatures et OfficeSource : https://github.com/Dano7762/offpatch/actions/runs/37302515562 (premier passage : contrôle hors ligne limité au premier fichier, source corrompue bloquée jusqu'à l'annulation du job à 120 min) et https://github.com/Dano7762/offpatch/actions/runs/37331201436 (passage complet, délai de 20 min sur l'installation corrompue).
  - R-01 à R-07 pour les SHA-1 dans les noms de fichiers et les premiers relevés Authenticode.
- Conclusion :
  - **Fichiers signés du dépôt** (SSU 2023, enablement package, .NET, cumulatives Windows 10 et Windows 11, plateforme Defender, mpam-fe.exe, ODT) : tous `Valid`, type `Authenticode`, chaîne jusqu'à **Microsoft Root Certificate Authority 2010**, horodatage « Microsoft Time-Stamp Service ». Signataire `CN=Microsoft Corporation, O=Microsoft Corporation, …` pour tous, **sauf la plateforme Defender** : `CN=Microsoft Windows Publisher, O=Microsoft Corporation, …` (émetteur Windows Production PCA 2023). Émetteurs intermédiaires : Microsoft Code Signing PCA 2010 (SSU 2023), Microsoft Windows Code Signing PCA 2024 (les autres). Le critère « signataire Microsoft Corporation » se vérifie donc sur l'organisation (`O=Microsoft Corporation`), pas sur le nom commun.
  - **Certificat expiré mais horodaté** : le SSU KB5031539 (2023) a une chaîne en `NotTimeValid` et reste `Valid` grâce à l'horodatage.
  - **Hors ligne** (cache d'URL vidé par `certutil -urlcache * delete`, sorties de powershell.exe bloquées au pare-feu, réseau injoignable vérifié depuis le processus de contrôle) : les 8 fichiers restent `Valid`, **aucun appel ne bloque**. Durées : 0 à 1,7 s pour les petits fichiers, 10,8 s pour la cumulative Windows 10 (0,9 Go), 62,8 s pour la cumulative Windows 11 ARM64 (4,4 Go) : c'est le calcul de l'empreinte, pas une attente réseau.
  - **Source Office** : les `.cab` (`v64.cab`, `i640.cab`, `s640.cab`, `a640_exp.cab`, cab de langue…) et les catalogues `.dat.cat` sont signés (`Valid`, Microsoft Corporation) ; les gros fichiers `stream.*.dat` **ne portent pas de signature Authenticode** (`UnknownError`, type `None`) : ils sont couverts par les catalogues `.dat.cat`, que `Get-AuthenticodeSignature` n'utilise pas tant qu'ils ne sont pas installés dans le système. L'ODT valide lui-même les fichiers (journal : `FileSignatureErrorDetection::Validate`, `CatalogFiles::GetCatalogName`).
  - **Source corrompue** (un octet inversé au milieu de `stream.x64.x-none.dat`, 2,8 Go ; CDN bloqué ; `AllowCdnFallback="FALSE"`) : l'ODT détecte le problème (tâche de flux `TASKSTATE_FAILED` dans `RepomanPipeline::Download`) mais **n'échoue pas** : Click-to-Run s'abonne aux événements « NETWORKON » et « TIMER » et attend le retour du réseau. `setup.exe` tournait toujours au bout de 20 min (deuxième passage), et de 120 min (premier passage, job annulé). Après l'arrêt de `setup.exe` : client Click-to-Run présent (`VersionToReport` 16.0.20430.20140) mais **aucun produit déclaré**.
- Décision (David, 2026-10-05 ; cahier des charges 1.12, 6.1, 7.1, 8.4, 8.5, 11) :
  - Authenticité vérifiée **côté dépôt, en ligne, au téléchargement** : `Status` = `Valid`, signataire de l'organisation Microsoft Corporation, chaîne vers une racine Microsoft. Un certificat expiré mais horodaté reste valide ; aucun contrôle sur la date d'expiration.
  - **Côté client** : SHA-256 du manifeste uniquement, sur les seuls fichiers utilisés par le plan, juste avant l'étape. Le contrôle Authenticode hors ligne fonctionne sans blocage s'il fallait le réactiver en option (compter environ une minute par cumulative Windows 11).
  - **Source Office** : SHA-256 de chaque fichier enregistré dans le manifeste au téléchargement (l'ODT a validé les fichiers à ce moment-là) ; revérification de toute la source utilisée avant tout `setup.exe /configure` ; au moindre écart, étape en erreur, ODT non lancé, fichiers fautifs listés dans le rapport.
  - **Garde-fou ODT** : délai maximal de 30 min (`client.odtTimeoutMinutes`), arrêt de `setup.exe`, étape en erreur « délai dépassé », journaux de l'ODT conservés, nouvelle détection d'Office par la version de `WINWORD.EXE`. Pas de délai sur DISM.
  - Le SHA-1 inscrit dans le nom des fichiers du catalogue reste un contrôle supplémentaire au téléchargement (R-01, R-03).

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
- Piste (2026-10-04, R-07, https://github.com/Dano7762/offpatch/actions/runs/37235902323) : source Office LTSC 2024 ProPlus 64 bits fr-fr, une version : 3 548 Mo (13 fichiers) ; deux versions côte à côte avant purge : 7 096 Mo.
- Piste (2026-10-04, R-07, https://github.com/Dano7762/offpatch/actions/runs/37236240851) : source Current 64 bits fr-fr (Home2024Retail) : 3 914 Mo pour 16.0.20430.20092, 3 605 Mo pour 16.0.20430.20140 après purge ; 7 518 Mo avec les deux versions. Prévoir environ 4 Go par source et par langue, le double entre deux purges.
- Piste (2026-10-04, R-06) : mpam-fe.exe x64 222 853 576 octets, ARM64 222 341 064 octets.
- Piste (2026-10-04, R-02) : KB5129195 x64 fait 4 639 422 594 octets (plus de 4 Gio), ARM64 4 391 570 921 octets. Un seul fichier dépasse donc la limite du FAT32. Confirmé par le téléchargement réel du workflow `depot-x64` (https://github.com/Dano7762/offpatch/actions/runs/37199155132) : 4 639 422 594 octets pour la cible, 533 761 740 pour KB5043080, 5,2 Go par cible Windows 11 au total.
- Sources :
- Conclusion :
- Décision :

## R-13 Domaines de téléchargement

Question : domaines réellement atteints après redirection pour le catalogue, mpam-fe.exe, l'ODT et le CDN Office.

Impact : `allowedDomains`.

- Statut : À vérifier
- Pistes (2026-10-04) :
  - Recherche et résolution des liens : `www.catalog.update.microsoft.com` (avec `www.`), pages `Search.aspx` et `DownloadDialog.aspx`. La liste du cahier des charges (6.1) porte `catalog.update.microsoft.com` sans `www.` : à compléter.
  - Fichiers des cumulatives : `catalog.sf.dl.delivery.mp.microsoft.com`, sans aucune redirection (requête HEAD avec suivi des redirections, workflow `depot-x64`, https://github.com/Dano7762/offpatch/actions/runs/37199155132). Absent de la liste actuelle.
  - Correspondance KB → build (R-01) : `learn.microsoft.com`. Absent de la liste actuelle.
  - Définitions Defender (R-06) : `go.microsoft.com` puis `definitionupdates.microsoft.com` (deux redirections 302). Le second est absent de la liste actuelle.
  - Office (R-07, https://github.com/Dano7762/offpatch/actions/runs/37235902323) : page de l'ODT `www.microsoft.com`, fichier de l'ODT `download.microsoft.com` ; domaines cités dans les journaux de l'ODT pendant `/download` : `officecdn.microsoft.com`, `f.c2r.ts.cdn.office.net`, `ecs.office.com`, `mrodevicemgr.officeapps.live.com`. Les deux derniers servent à la configuration et au suivi, pas aux fichiers. Décision de David du 2026-10-04 (cahier des charges 1.9, 6.1) : `allowedDomains` ne concerne que les téléchargements faits par OffPatch, pas le trafic propre de l'ODT ; ces domaines ne sont donc pas à y ajouter.
  - Fichiers anciens du catalogue (SSU Windows 10 de 2023, R-04) : `catalog.s.download.windowsupdate.com`, sans redirection (https://github.com/Dano7762/offpatch/actions/runs/37202749032). Absent de la liste actuelle.
- Sources :
- Conclusion :
- Décision :

## R-14 Moteur d'installation des paquets

Question : `dism.exe /Online /Add-Package` ou `Add-WindowsPackage -Online` ? Codes retour, gestion du 3010, emplacement des journaux, comportement avec un dossier contenant plusieurs .msu. Un outil tiers comme W10UI apporterait-il quelque chose de plus ?

Impact : exécuteur des étapes Windows.

- Statut : À vérifier
- Mesuré (2026-10-04, runner `windows-11-arm`, https://github.com/Dano7762/offpatch/actions/runs/37199356179) : `dism.exe /English /Online /Add-Package /PackagePath:<fichier .msu> /NoRestart /LogPath:<fichier>` renvoie 0 et « The operation completed successfully » pour une checkpoint ou une cumulative déjà installée. Le journal DISM contient des lignes `Error … CMitigationManager::CheckApplicability … 0x80070032` sans conséquence sur le résultat : l'exécuteur ne doit pas juger un succès sur la présence du mot « Error » dans le journal.
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
