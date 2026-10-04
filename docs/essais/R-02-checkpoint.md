# Essais R-02 : cumulatives checkpoint

Les essais réels passent par GitHub Actions, sur le dépôt privé `Dano7762/offpatch`, sur des runners hébergés jetables. Claude Code les lance et les lit avec `gh`. Rien n'est exécuté sur la machine de développement.

Paquets de référence : KB5129195 (cumulative de septembre 2026, 26x00.9457) et sa checkpoint KB5043080 (26100.1742).

## Workflows

| Workflow | Runner | Déclenchement | Ce qu'il fait | Points |
|---|---|---|---|---|
| `r02-arm64.yml` | `windows-11-arm` (Windows 11 client ARM64, 2 vCPU, 14 Go de SSD en dépôt privé) | manuel, entrée `kb` | droits admin, espace libre, build/UBR, `Get-HotFix`, `dism /Get-Packages` ; téléchargement de l'entrée ARM64 (un fichier par dossier nommé par son SHA-256) ; méthode 1 : `/Add-Package /NoRestart` sur la checkpoint puis la cible ; seconde passe identique pour le cas « déjà installé » ; relevé final ; journaux DISM, CBS et relevés en artefact | R-02, R-14, R-09 |
| `depot-x64.yml` | `windows-2025` | manuel, entrée `kb` | téléchargement de l'entrée x64, SHA-1 comparé au nom de fichier, SHA-256, Authenticode, taille, domaines traversés par les redirections ; rapport en artefact (pas les .msu) | R-10, R-12, R-13 |
| `ci.yml` | `windows-2025` | chaque push | PSScriptAnalyzer et Pester 5 sous Windows PowerShell 5.1 | — |

Scripts appelés : `tests/runner/Invoke-R02CheckpointTest.ps1`, `tests/runner/Save-CatalogEntryFile.ps1`, `tests/runner/Write-DownloadSummary.ps1`. Le script d'essai R-02 refuse de s'exécuter hors d'un runner GitHub (`GITHUB_ACTIONS`).

## Commandes

```bash
gh workflow run r02-arm64.yml -f kb=KB5129195
gh run list --workflow r02-arm64.yml --limit 1
gh run view <id> --log
gh run download <id> --dir scratch/runs/<id>
```

## Lecture des résultats

- `resume.md` et `r02-result.json` : build avant et après, et pour chaque étape le code retour DISM (décimal et hexadécimal), la durée et l'état « redémarrage en attente ».
- `packages-avant.txt` et `packages-apres.txt` : forme du nom des paquets de cumulative dans la liste DISM (détection de la checkpoint).
- `hotfix-*.txt` : ce que voit `Get-HotFix`.
- `dism-*.log`, `CBS.zip` : journaux détaillés.

## Limites connues

- Pas de redémarrage possible sur un runner : on mesure l'installation jusqu'à « redémarrage en attente », pas la build obtenue après redémarrage, ni le nombre de redémarrages.
- Si le runner est déjà en 26x00.9457 ou plus, l'essai ne mesure que les codes « déjà installé ». Il faudra relancer `r02-arm64.yml` avec la cumulative du Patch Tuesday du 13 octobre 2026.
- Pas de Windows 11 x64 client parmi les runners standard (`windows-2025` est un Windows Server 2025 : DISM y refuserait la cumulative cliente).
- Pas de support sans checkpoint : les runners ont une image récente.

Ces points sont à valider sur intervention réelle (voir `docs/RECHERCHE.md`), en commençant par l'action `Plan` en lecture seule.
