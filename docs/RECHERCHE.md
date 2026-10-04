# Points à vérifier

Chaque point est traité en phase 0, avant d'écrire le code qui en dépend. Sources prioritaires : learn.microsoft.com, support.microsoft.com, le Microsoft Update Catalog lui-même. Un forum peut donner une piste, jamais une conclusion.

Pour chaque point, remplir les quatre champs en dessous de la question. Les scripts d'essai vont dans `scratch/`, jamais dans `app/`.

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
  - Le catalogue renvoie au plus 25 résultats par page. La requête générique `2026-09 Cumulative Update for Windows 11, version` atteint ce plafond et perd des entrées (KB5124008 absent du résultat), alors que la requête limitée à une version en renvoie 8. On envoie donc une requête par version listée dans la configuration : `AAAA-MM Cumulative Update for Windows 11, version 24H2`, puis `25H2`, puis `26H2`, et pour Windows 10 `AAAA-MM Cumulative Update for Windows 10 Version 22H2` (14 résultats). Les résultats sont fusionnés. Requêtes lancées pour le mois courant, puis le précédent si rien n'est trouvé. Si une page revient avec 25 lignes, l'outil le signale dans le journal (risque de troncature). Contrôle des motifs sur les titres réels : `scratch/r01-check-patterns.ps1`. Valeurs proposées pour `catalog-queries.json` (à poser au bilan de phase) :
    - `win11-x64` / `windows-lcu` : include `^\d{4}-\d{2} Cumulative Update for Windows 11, version (24H2|25H2|26H2) for x64-based Systems \(KB\d+\) \(\d+\.\d+\)$`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|26H1|arm64`.
    - `win11-arm64` / `windows-lcu` : même motif avec `arm64-based Systems`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|26H1|x64-based`.
    - `win10-x64` / `windows-lcu` : include `^\d{4}-\d{2} Cumulative Update for Windows 10 Version 22H2 for x64-based Systems \(KB\d+\)$`, exclude `Preview|Dynamic|Hotpatch|Server|\.NET|21H2|x86|ARM64`.
  - Règle de sélection Windows 11 : regrouper les entrées par KB, puis garder le KB dont l'UBR (dernier nombre du titre) est le plus élevé. Une seule copie des fichiers par architecture, quelle que soit la version du titre.
  - Règle de sélection Windows 10 : pas de build dans le titre, donc tri par date de publication la plus récente parmi les entrées 22H2 x64. La build résultante sera établie en R-09.
  - Le motif d'exemple du cahier des charges (6.2, `"search": "Cumulative Update Windows 11 x64"`) ramène aussi les préversions, les dynamiques et 26H1, et le catalogue limite une page à 25 résultats : il faut la requête datée ci-dessus et l'exclusion de 26H1. Simple exemple de format, pas de modification du cahier des charges nécessaire ; la règle de sélection « UBR le plus élevé » sera ajoutée au bilan de phase, avec ton accord.
  - Pistes notées pour d'autres points : nom de fichier contenant un SHA-1 (R-10), domaine de téléchargement `catalog.sf.dl.delivery.mp.microsoft.com` (R-13), taille affichée par entrée 4933,5 Mo pour Windows 11 x64 et 4770,5 Mo pour ARM64 (deux .msu, répartition par fichier inconnue), 895,9 Mo pour Windows 10 x64 (R-12).

## R-02 Cumulatives « checkpoint »

Question : sur une installation récente de Windows 11 24H2, 25H2 ou 26H2, quelles cumulatives checkpoint faut-il installer avant la dernière cumulative ? Comment DISM les traite-t-il quand tous les fichiers .msu sont dans un même dossier ? Quel ordre et combien de redémarrages ?

Impact : catégorie `windows-checkpoint`, ordre du plan, champ `prerequisites` du manifeste.

- Statut : À vérifier
- Sources :
- Conclusion :
- Décision :

## R-03 Enablement package 26H2

Question : numéro de KB, présence au catalogue pour x64 et ARM64, build minimale requise. Peut-il s'installer juste après la cumulative, avant le redémarrage ?

Impact : catégorie `windows-ekb`, regroupement des redémarrages.

- Statut : À vérifier
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
