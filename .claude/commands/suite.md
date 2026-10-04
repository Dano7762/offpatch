---
description: Reprendre le projet à la prochaine tâche du backlog
---

Lis `CLAUDE.md`, puis `docs/TODO.md`.

1. Repère la première tâche non cochée de la phase en cours. Si la phase précédente n'est pas terminée, signale-le et reprends-la.
2. Si la tâche est marquée [VM] : si un runner GitHub hébergé permet le test, écris ou adapte le workflow (déclenchement manuel), lance-le avec `gh`, lis les journaux et les artefacts. Sinon, rédige la procédure pas à pas pour David sur intervention réelle (en commençant par l'action `Plan` en lecture seule, commandes à lancer, résultat attendu) et attends son retour.
3. Si la tâche dépend d'un point de `docs/RECHERCHE.md` encore « À vérifier », traite ce point d'abord.
4. Annonce en deux ou trois phrases ce que tu vas faire, puis fais-le jusqu'au bout sans demander de validation intermédiaire : code, tests, analyse statique.
5. Coche la tâche, ajoute une ligne au journal des sessions et fais le commit.
6. Termine par un résumé court : ce qui est fait, ce qui reste, la prochaine tâche.

$ARGUMENTS
