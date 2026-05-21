# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Langues : [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Faites travailler les AI agents à partir de vraies tâches projet.

Maestro relie **systèmes de projet, dépôts Git et coding agents** dans un même flux d’exécution de tâches d’ingénierie.

Au lieu de surveiller une conversation IA à la fois, Maestro peut lire des tâches nouvelles ou prêtes à être traitées depuis Linear, TAPD ou d’autres systèmes, créer un espace de travail isolé pour chaque tâche, préparer le dépôt Git cible, lancer l’AI Agent adapté, enregistrer ce qui s’est passé et réécrire le résultat dans le système de projet.

Maestro n’est pas un autre coding agent.

Il aide les équipes à répondre aux questions qui apparaissent quand les agents deviennent vraiment utiles : d’où vient la tâche, d’où vient le code, où l’agent s’exécute, comment plusieurs tâches peuvent tourner en parallèle, ce qui a changé, si le résultat est fiable, et comment l’équipe peut relire, reprendre ou récupérer l’exécution.

> **Symphony a montré que les tâches projet peuvent piloter des agents. Maestro transforme ce modèle en plateforme d’ingénierie exploitable.**

---

## Un exemple

Imaginons qu’une nouvelle tâche apparaisse dans TAPD ou Linear :

> La page de paiement échoue quand un utilisateur applique deux coupons.

Avec Maestro, cette tâche peut devenir une exécution d’agent visible :

1. Maestro synchronise ou lit la tâche depuis TAPD, Linear ou un autre système de projet.
2. Maestro crée un espace de travail isolé dans son propre environnement d’exécution.
3. Maestro clone ou checkout le dépôt Git cible dans cet espace.
4. Maestro lance Codex, Claude Code, OpenCode ou un autre agent pris en charge avec la tâche, la copie du dépôt et les outils autorisés.
5. L’agent analyse la copie du dépôt et prépare une modification de code, un résultat d’analyse ou une suggestion de revue.
6. Maestro enregistre diff, logs, appels d’outils, résumé et liens associés.
7. Maestro réécrit le résultat dans le système de projet pour que l’équipe puisse relire, continuer ou reprendre.

Le but n’est pas de laisser un agent tourner à l’aveugle. Le but est celui-ci :

> **Une tâche projet devient une exécution d’ingénierie isolée, enregistrée, relisible et transférable.**

L’espace isolé est important : chaque tâche possède son propre répertoire, sa propre copie du dépôt, ses logs et ses fichiers temporaires. Plusieurs projets et tâches peuvent donc tourner en parallèle sans se contaminer. En cas d’échec, il est plus simple d’inspecter, nettoyer et relancer.

---

## Pourquoi c’est important

Les coding agents deviennent meilleurs pour écrire du code. Les équipes ont besoin de plus que de la génération de code.

Elles ont besoin de réponses concrètes :

- De quel système de projet vient la tâche ?
- À quel dépôt Git et quelle branche correspond-elle ?
- Quel agent doit l’exécuter ?
- Où l’agent s’exécute-t-il ?
- Comment plusieurs exécutions restent-elles isolées ?
- Qu’est-ce qui a changé ?
- Les humains peuvent-ils relire le résultat ?
- Que se passe-t-il en cas d’échec ?
- Comment l’équipe comprend-elle ce qui s’est passé ?

Maestro est conçu autour de ces questions.

---

## Ce que vous pouvez faire avec Maestro

### 1. Transformer une tâche de bug en Pull Request

Un bug apparaît dans TAPD ou Linear. Maestro lit la tâche, crée un espace de travail isolé, prépare le dépôt Git cible, lance un agent, laisse l’agent analyser et modifier le code, puis réécrit le lien de PR, le résumé et les questions ouvertes dans la tâche.

### 2. Analyser une exigence avant de coder

Si une exigence n’est pas encore claire, Maestro peut demander à un agent de produire le périmètre, les risques, les critères d’acceptation et les questions de clarification avant l’implémentation.

### 3. Clarifier une tâche qui ne peut pas encore démarrer

Quand il manque du contexte, Maestro peut faire émerger hypothèses, blocages et questions au lieu de laisser l’agent deviner.

### 4. Trier le travail entrant

Maestro peut aider à classer de nouvelles tâches, suggérer une priorité, identifier les risques et recommander le prochain état.

### 5. Comparer différents coding agents

Exécutez des tâches similaires avec Codex, Claude Code ou OpenCode et comparez résultats, modes d’échec, logs et traces de livraison.

### 6. Essayer localement sans comptes réels

Utilisez le flux local `memory/no_repo/mock` pour comprendre Maestro sans connecter Linear, TAPD, GitHub, CNB, Codex, Claude Code ou OpenCode.

---

## Intégrations actuellement prises en charge

Les systèmes ci-dessous sont des **intégrations prises en charge et des templates fournis**, pas des systèmes embarqués dans Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code et OpenCode restent des systèmes ou outils externes. Maestro les connecte et les orchestre.

Adaptateurs de systèmes de projet :

- Linear
- TAPD
- Memory, pour tests locaux et démos

Adaptateurs d’agent :

- Codex
- Claude Code
- OpenCode
- Mock, pour tests locaux et démos

Adaptateurs de plateformes de code :

- GitHub
- CNB
- Memory, pour tests locaux et démos

Templates de workflow fournis :

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro est conçu pour s’étendre à davantage de systèmes de projet, plateformes de code, agents et templates de workflow.

---

## Comment ça fonctionne

```text
Tâche dans un système de projet
   ↓
Maestro lit/synchronise la tâche et décide s’il faut la traiter
   ↓
Maestro crée un espace de travail isolé dans son propre environnement d’exécution
   ↓
Le dépôt Git cible est préparé dans cet espace
   ↓
Un AI Agent s’exécute avec la tâche, la copie du dépôt et les outils autorisés
   ↓
L’agent produit une modification de code, un résultat d’analyse ou une suggestion de revue
   ↓
Maestro enregistre diffs, logs, appels d’outils, résumés et liens
   ↓
Maestro réécrit le résultat dans le système de projet pour revue ou passage de relais
```

Pour les développeurs, ce flux s’organise autour de quelques points d’extension :

- **Systèmes de projet** : d’où viennent les tâches, par exemple Linear ou TAPD.
- **Dépôts Git et plateformes de code** : d’où le code est cloné et où branches, PR, revues et checks se produisent.
- **Agents** : qui exécute le travail, par exemple Codex, Claude Code ou OpenCode.
- **Workflows** : quel type de travail est réalisé : correction de bug, analyse d’exigence, clarification de tâche, triage ou suggestion de revue.
- **Espaces de travail et environnements d’exécution** : où chaque exécution se déroule, comment elle est isolée et comment elle peut tourner en parallèle.
- **Traces** : logs, diffs, commentaires de tâches, résumés et autres informations relisibles.

---

## Quick start

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
cd elixir
mise trust
mise install
cd ..
make -C elixir deps
make -C elixir test
make -C elixir build
cd elixir
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Ouvrez le dashboard optionnel :

```text
http://localhost:4000
```

Cette démo utilise des données en mémoire et un Mock Agent. C’est le moyen le plus sûr de comprendre le projet avant de connecter de vrais systèmes.

> La marque publique est **Maestro**. Certains noms de runtime utilisent encore `symphony` pour compatibilité, notamment l’entrée CLI et certaines variables d’environnement.

---

## Utiliser de vrais systèmes

Après la démo locale, vous pouvez connecter un vrai système de projet, un dépôt Git et un coding agent.

### Exemple : TAPD + GitHub + Codex

```bash
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template tapd/github/codex \
  --port 4000
```

### Exemple : Linear + GitHub + Codex

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex \
  --port 4000
```

Avant d’utiliser de vrais dépôts ou des identifiants à privilèges élevés, lisez :

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Ce qu’est Maestro, et ce qu’il n’est pas

Maestro est :

- une plateforme d’exécution de tâches d’ingénierie reliant systèmes de projet, dépôts Git et coding agents ;
- une façon d’exécuter des AI agents depuis de vraies tâches projet ;
- une couche de workflow pour coding, analyse d’exigences, clarification de tâches, triage et suggestions de revue ;
- une façon plus sûre de tester, comparer et gérer différents coding agents.

Maestro n’est pas :

- un nouveau grand modèle de langage ;
- un remplacement de Codex, Claude Code ou OpenCode ;
- un outil pour contourner la revue, les tests ou le jugement de release de l’équipe ;
- un système auquel donner accès au dépôt avant de le laisser tourner sans surveillance.

---

## Statut du projet

Maestro est un logiciel en phase précoce et en développement actif.

Il convient pour :

- apprendre comment des workflows d’agents pilotés par tâches peuvent fonctionner ;
- exécuter des démos locales memory/mock ;
- prototyper de nouvelles intégrations ;
- expérimenter avec de vrais systèmes dans des environnements contrôlés.

Soyez particulièrement prudent avant de :

- permettre aux agents de modifier de vrais dépôts ou pousser des branches ;
- permettre aux agents d’écrire états ou commentaires dans de vrais systèmes de projet ;
- utiliser des identifiants à privilèges élevés ou des tokens personnels ;
- partager un même environnement d’exécution entre plusieurs équipes ;
- avancer vers test, release ou production sans revue humaine.

Règle directrice :

> **Automatiser avec ambition. Poser des gates avec soin. Garder la trace visible.**

---

## En savoir plus

- [Roadmap](./ROADMAP.fr.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Attribution

Maestro started as a fork of [OpenAI Symphony](https://github.com/openai/symphony). Symphony demonstrated that project tasks can drive coding agents. Maestro extends that idea into a broader platform for real engineering workflows.

---

## License

Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements. Review `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, and `THIRD_PARTY_LICENSES.md` before using or distributing Maestro.
