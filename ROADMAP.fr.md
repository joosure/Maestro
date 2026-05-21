# Maestro Roadmap

Langues : [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [Français](./ROADMAP.fr.md) · [More](./LANGUAGES.md)

## Objectif

Maestro a un objectif simple :

> **Rendre les AI agents plus faciles, plus sûrs et plus fiables pour de vraies équipes d’ingénierie.**

Beaucoup de coding agents savent déjà écrire du code. Les équipes ont besoin de plus que de la génération de code :

- le travail doit venir de vrais systèmes comme TAPD, Linear et de futures plateformes ;
- le code doit venir d’un dépôt Git et d’une branche configurés explicitement ;
- chaque exécution doit avoir un espace de travail isolé pour éviter les interférences entre tâches ;
- les personnes doivent comprendre ce que l’agent a fait, ce qui a changé et pourquoi il a échoué ;
- les étapes risquées doivent rester relisibles ;
- les équipes doivent pouvoir élargir l’usage progressivement, pas ouvrir tous les droits dès le premier jour.

Cette roadmap est organisée par valeur utilisateur, pas par noms de modules internes.

---

## Court terme : rendre Maestro plus facile à essayer

Un nouvel utilisateur doit comprendre et lancer Maestro sans apprendre toute l’architecture d’abord.

Travail prévu :

- une démo locale plus simple ;
- des instructions Quick Start plus claires ;
- captures, GIFs ou courtes vidéos ;
- tâches d’exemple montrant le flux complet ;
- explication claire de l’intérêt des espaces isolés : parallélisme, isolation, nettoyage et relecture ;
- explication des noms de compatibilité `symphony` restants ;
- chemin clair de la démo locale vers une configuration réelle.

Scénarios à rendre plus faciles à démontrer :

- tâche TAPD vers GitHub Pull Request ;
- tâche Linear vers GitHub Pull Request ;
- analyse d’exigence avant codage ;
- triage du travail entrant ;
- suggestions de reviewer ;
- comparaison de Codex, Claude Code et OpenCode sur des tâches similaires.

Succès : un nouveau lecteur peut répondre en quelques minutes :

> « Que fait Maestro, et pourquoi mon équipe pourrait en avoir besoin ? »

---

## Ensuite : connecter les agents aux vrais workflows projet

Maestro doit aider les agents à travailler depuis les systèmes que les équipes utilisent déjà, sans imposer une nouvelle file de tâches.

Travail prévu :

- améliorer les flux TAPD et Linear actuels ;
- rendre états, commentaires, liens et résultats plus compréhensibles ;
- rendre les workflow templates plus faciles à trouver, copier et adapter ;
- prendre en charge plus de tâches courantes : bugs, petites features, analyse d’exigences, clarification, triage et suggestions de revue ;
- distinguer clairement le support actuel des cibles d’extension futures ;
- préparer des intégrations comme Jira, GitHub Issues, GitLab, Gitea, Bitbucket et Feishu Project.

Succès : les équipes peuvent partir de leur workflow projet existant au lieu de changer leur façon de gérer le travail pour utiliser des agents.

---

## Moyen terme : rendre le travail de l’agent plus fiable

Une équipe ne devrait pas faire confiance à une exécution seulement parce que l’agent dit « terminé ».

Travail prévu :

- historique d’exécution plus clair ;
- résumés plus lisibles ;
- meilleurs liens entre tâches, changements Git, logs et éléments de revue ;
- raisons d’échec plus claires ;
- meilleure redaction des logs ;
- dashboard plus utile ;
- checkpoints visibles avant d’écrire dans de vrais systèmes, pousser des branches ou créer des PRs ;
- séparation claire entre démo locale, évaluation de confiance, pilote d’équipe et production.

Succès : un reviewer peut répondre :

- Qu’a fait l’agent ?
- Depuis quelle tâche et quel dépôt Git a-t-il travaillé ?
- Qu’est-ce qui a changé ?
- Pourquoi s’est-il arrêté ?
- Qu’est-ce qui nécessite encore une confirmation humaine ?
- Est-il sûr de continuer ?

---

## Long terme : aider les équipes à utiliser les agents à grande échelle

Une démo avec un seul agent est utile. L’usage en équipe demande une exploitation plus solide.

Travail prévu :

- exécuter plusieurs tâches en parallèle en sécurité ;
- garder des espaces et des traces séparés pour différents projets et tâches ;
- choisir différents agents selon le type de tâche ;
- gérer comptes, identifiants, quotas et coûts plus clairement ;
- améliorer les environnements d’exécution d’équipe ;
- améliorer retry et récupération ;
- soutenir des points d’approbation humaine plus clairs ;
- aider les équipes à comparer l’efficacité réelle de différents agents et workflows.

Succès : les équipes peuvent élargir l’usage des agents progressivement tout en gardant sécurité, coût et qualité sous contrôle.

---

## Documentation et communauté

Maestro doit être compréhensible avant d’être impressionnant.

Travail prévu :

- garder le README principal court et basé sur des exemples ;
- déplacer les détails techniques profonds dans des docs séparées ;
- maintenir activement English et Simplified Chinese ;
- garder les autres traductions disponibles et accueillir les améliorations communautaires ;
- ajouter des guides de contribution pour systèmes de projet, agents, plateformes de code et workflow templates ;
- publier plus d’exemples de scénarios réels d’ingénierie.

Succès : les contributeurs trouvent un point d’entrée utile sans lire toute la base de code.

---

## Non-objectifs pour l’instant

Maestro ne cherche pas à aider les équipes à contourner la revue, les tests ou le jugement de release.

Nous privilégions :

- connecter les agents à de vraies tâches ;
- rendre visibles la source du code et la source de la tâche ;
- garder le processus traçable ;
- maintenir le contrôle humain aux étapes risquées ;
- préserver des traces utiles ;
- élargir l’automatisation seulement quand la confiance augmente.

L’automatisation doit grandir avec des preuves, pas avec des souhaits.

---

## Priorité actuelle

La priorité actuelle est de rendre Maestro plus facile à comprendre, essayer et évaluer en sécurité :

1. simplifier le README public ;
2. ajouter une roadmap en langage clair ;
3. améliorer la démo locale ;
4. décrire le support actuel sans présenter des systèmes externes comme « embarqués » ;
5. expliquer pourquoi les espaces isolés comptent ;
6. ajouter des exemples avec TAPD, Linear, GitHub, CNB et de vraies combinaisons d’agents ;
7. garder les détails techniques disponibles sans obliger chaque nouveau lecteur à commencer par là.

---

## Contribuer

Contributions utiles :

- meilleurs exemples ;
- documentation plus claire ;
- workflow templates plus sûrs ;
- nouvelles intégrations de systèmes de projet ;
- nouvelles intégrations de coding agents ;
- nouvelles intégrations de plateformes de code ;
- améliorations du dashboard ;
- tests sur de vrais workflows ;
- relecture de traduction par locuteurs natifs.

Commencez par le flux local memory/mock, puis avancez progressivement vers de vrais systèmes.
