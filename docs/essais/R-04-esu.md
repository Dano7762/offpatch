# Relevés R-04 : Windows 10 22H2 et ESU

Aucun runner GitHub ne fournit Windows 10 client (`windows-2022` et `windows-2025` sont des Windows Server). Ces relevés se font donc sur intervention réelle, sur un PC Windows 10 22H2 que tu as sous la main. On commence en **lecture seule** : rien n'est installé ni modifié.

## Étape 1 : relevé en lecture seule (sur chaque PC Windows 10 rencontré)

Idéalement : un PC inscrit à l'ESU grand public, un PC avec une clé ESU entreprise (MAK) si tu en as un, et un PC non inscrit.

PowerShell **en administrateur** (la lecture des licences ne demande pas l'élévation, mais `dism /Get-Packages` si) :

```powershell
$out = Join-Path $env:USERPROFILE 'Desktop\R04-releve.txt'
& {
    '=== Système'
    $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    '{0}.{1} {2} {3}' -f $v.CurrentBuild, $v.UBR, $v.DisplayVersion, $v.EditionID
    (Get-CimInstance Win32_OperatingSystem).Caption
    '=== Domaine, Entra, MDM'
    (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    dsregcmd.exe /status | Select-String -Pattern 'AzureAdJoined|WorkplaceJoined|DomainJoined|MdmUrl'
    '=== Licences ESU (identifiants d''activation documentés)'
    $ids = 'f520e45e-7413-4a34-a497-d2765967d094', '1043add5-23b1-4afb-9a0f-64343c8f3f8d', '83d49986-add3-41d7-ba33-87c7bfb5c0fb'
    $filter = ($ids | ForEach-Object { "ID='$_'" }) -join ' OR '
    Get-CimInstance SoftwareLicensingProduct -Filter $filter |
        Format-List Name, Description, ID, LicenseStatus, PartialProductKey, GracePeriodRemaining, LicenseFamily
    '=== Tous les produits de licence dont le nom ou la description évoque ESU'
    Get-CimInstance SoftwareLicensingProduct -Filter "Name LIKE '%ESU%' OR Description LIKE '%ESU%' OR Description LIKE '%Extended%'" |
        Format-List Name, Description, ID, LicenseStatus, PartialProductKey, LicenseFamily
    '=== Mises à jour installées'
    Get-HotFix | Sort-Object InstalledOn | Format-Table -AutoSize HotFixID, Description, InstalledOn
    '=== Paquets DISM (cumulatives et préparation ESU)'
    dism.exe /English /Online /Get-Packages /Format:Table | Select-String -Pattern 'RollupFix|ESU|5126256|5072653'
} *>&1 | Out-File -FilePath $out -Encoding UTF8
"Relevé écrit dans $out"
```

Note pour chaque PC ce que Paramètres > Mise à jour et sécurité > Windows Update affiche au sujet de l'ESU (inscrit ou non, et si oui jusqu'à quelle date).

Le relevé ne contient ni clé de produit complète ni secret : `PartialProductKey` ne montre que les 5 derniers caractères. Relis-le quand même avant de me l'envoyer.

## Ce que le relevé doit trancher

1. **ESU entreprise** : une licence ESU active apparaît-elle avec un des trois identifiants et `LicenseStatus = 1` ? (attendu d'après la documentation Microsoft)
2. **ESU grand public** : l'inscription laisse-t-elle une trace lisible hors ligne (un produit de licence ESU, avec quel identifiant et quel état) ? Aucune documentation Microsoft ne le dit.
3. **PC non inscrit** : quels produits ESU existent, avec quel état (attendu : absents, ou présents avec `LicenseStatus = 0` si le paquet de préparation est installé) ?

## Étape 2 (plus tard, avec ton accord) : installation d'une cumulative par DISM

À ne faire que sur un PC que tu peux remettre en état. Elle répondra à la dernière question de R-04 : la cumulative ESU téléchargée depuis le catalogue s'installe-t-elle par DISM sur un PC inscrit, et que se passe-t-il sur un PC non inscrit (code retour, message) ? Elle correspond aux tests T4 et T5 du cahier des charges et sera menée avec l'action `Plan` de l'outil dès qu'elle existera.
