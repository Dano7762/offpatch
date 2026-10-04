---
description: Analyse statique et tests, puis correction des erreurs
---

1. Lance PSScriptAnalyzer avec les paramètres du projet (commande dans `CLAUDE.md`).
2. Lance Pester sur `./tests`.
3. Corrige les erreurs et les tests en échec. Ne modifie un test pour le faire passer que s'il est lui-même faux, et explique pourquoi.
4. Vérifie au passage que les fichiers `.ps1`, `.psm1` et `.psd1` modifiés sont bien en UTF-8 avec BOM et qu'aucune syntaxe absente de PowerShell 5.1 n'a été introduite.
5. Relance les deux outils jusqu'à obtenir zéro erreur, puis donne le bilan : avertissements restants et raison pour laquelle ils sont acceptables.
