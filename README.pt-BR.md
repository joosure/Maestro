# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Idiomas: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Faça AI agents trabalharem a partir de tarefas reais de projeto.

Maestro conecta **sistemas de projeto, repositórios Git e coding agents** em um fluxo único de execução de tarefas de engenharia.

Em vez de acompanhar uma conversa de IA por vez, Maestro pode ler tarefas novas ou prontas em sistemas como Linear ou TAPD, criar uma área de trabalho isolada para cada tarefa, preparar o repositório Git alvo, iniciar o AI Agent adequado, registrar o que aconteceu e escrever o resultado de volta no sistema de projeto.

Maestro não é outro coding agent.

Ele ajuda equipes a responder às perguntas que aparecem quando agents passam a ser úteis: de onde vem a tarefa, de onde vem o código, onde o agent roda, como executar várias tarefas em paralelo, o que mudou, se o resultado é confiável e como a equipe pode revisar ou recuperar a execução.

> **Symphony mostrou que tarefas de projeto podem dirigir agents. Maestro transforma esse padrão em uma plataforma de engenharia operável.**

---

## Um exemplo

Imagine que uma nova tarefa aparece no TAPD ou no Linear:

> A página de checkout falha quando um usuário aplica dois cupons.

Com Maestro, essa tarefa pode virar uma execução visível de agent:

1. Maestro sincroniza ou lê a tarefa a partir do TAPD, Linear ou outro sistema de projeto.
2. Maestro cria uma área de trabalho isolada no seu próprio ambiente de execução.
3. Maestro clona ou faz checkout do repositório Git alvo dentro dessa área.
4. Maestro inicia Codex, Claude Code, OpenCode ou outro agent suportado com a tarefa, a cópia do repositório e as ferramentas permitidas.
5. O agent analisa a cópia do repositório e prepara uma alteração de código, um resultado de análise ou uma sugestão de revisão.
6. Maestro registra diff, logs, chamadas de ferramentas, resumo e links relacionados.
7. Maestro escreve o resultado de volta no sistema de projeto para que a equipe possa revisar, continuar ou assumir.

A ideia não é deixar um agent rodar às cegas. A ideia é esta:

> **Uma tarefa de projeto se transforma em uma execução de engenharia isolada, registrada, revisável e transferível.**

A área de trabalho isolada é importante porque cada tarefa tem seu próprio diretório, cópia do repositório, logs e arquivos temporários. Vários projetos e tarefas podem rodar em paralelo sem se contaminar; quando algo falha, fica mais fácil inspecionar, limpar e tentar novamente.

---

## Por que isso importa

Coding agents estão cada vez melhores em escrever código. Equipes precisam de mais do que geração de código.

Elas precisam de respostas práticas:

- De qual sistema de projeto a tarefa vem?
- A qual repositório Git e branch ela corresponde?
- Qual agent deve executá-la?
- Onde o agent roda?
- Como várias execuções permanecem isoladas?
- O que mudou?
- Humanos conseguem revisar o resultado?
- O que acontece se falhar?
- Como a equipe entende o que aconteceu?

Maestro é construído em torno dessas perguntas.

---

## O que você pode fazer com Maestro

### 1. Transformar uma tarefa de bug em Pull Request

Um bug aparece no TAPD ou Linear. Maestro lê a tarefa, cria uma área de trabalho isolada, prepara o repositório Git alvo, inicia um agent, permite que o agent analise e altere o código, e escreve o link do PR, o resumo e as perguntas abertas de volta na tarefa.

### 2. Analisar um requisito antes de codar

Se um requisito ainda não está claro, Maestro pode pedir ao agent que produza escopo, riscos, critérios de aceitação e perguntas de esclarecimento antes da implementação.

### 3. Refinar uma tarefa que ainda não pode começar

Se falta contexto, Maestro pode expor suposições, bloqueios e perguntas em vez de deixar o agent adivinhar.

### 4. Classificar trabalho entrante

Maestro pode ajudar a classificar novas tarefas, sugerir prioridade, identificar riscos e recomendar o próximo estado.

### 5. Comparar diferentes coding agents

Execute tarefas parecidas com Codex, Claude Code ou OpenCode e compare resultados, modos de falha, logs e registros de entrega.

### 6. Testar localmente sem contas reais

Use o fluxo local `memory/no_repo/mock` para entender Maestro sem conectar Linear, TAPD, GitHub, CNB, Codex, Claude Code ou OpenCode.

---

## Integrações suportadas atualmente

Os sistemas abaixo são **integrações suportadas e templates incluídos**, não sistemas embutidos dentro do Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code e OpenCode continuam sendo sistemas ou ferramentas externas. Maestro os conecta e orquestra.

Adaptadores de sistema de projeto:

- Linear
- TAPD
- Memory, para testes e demos locais

Adaptadores de agent:

- Codex
- Claude Code
- OpenCode
- Mock, para testes e demos locais

Adaptadores de plataforma de código:

- GitHub
- CNB
- Memory, para testes e demos locais

Templates de workflow incluídos:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro foi projetado para crescer com mais sistemas de projeto, plataformas de código, agents e templates de workflow.

---

## Como funciona

```text
Tarefa em um sistema de projeto
   ↓
Maestro lê/sincroniza a tarefa e decide se deve tratá-la
   ↓
Maestro cria uma área de trabalho isolada em seu próprio ambiente de execução
   ↓
O repositório Git alvo é preparado dentro dessa área
   ↓
Um AI Agent roda com a tarefa, a cópia do repositório e as ferramentas permitidas
   ↓
O agent produz uma alteração de código, resultado de análise ou sugestão de revisão
   ↓
Maestro registra diffs, logs, chamadas de ferramentas, resumos e links
   ↓
Maestro escreve o resultado de volta no sistema de projeto para revisão ou passagem de bastão
```

Para desenvolvedores, o mesmo fluxo se organiza em alguns pontos extensíveis:

- **Sistemas de projeto**: de onde vêm as tarefas, como Linear ou TAPD.
- **Repositórios Git e plataformas de código**: de onde o código é clonado e onde branches, PRs, revisões e checks acontecem.
- **Agents**: quem executa o trabalho, como Codex, Claude Code ou OpenCode.
- **Workflows**: que tipo de trabalho acontece, como corrigir bugs, analisar requisitos, refinar tarefas, classificar trabalho ou sugerir revisões.
- **Áreas de trabalho e ambientes de execução**: onde cada execução acontece, como é isolada e como roda em paralelo.
- **Registros**: logs, diffs, comentários de tarefas, resumos e outras informações revisáveis.

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

Abra o dashboard opcional:

```text
http://localhost:4000
```

Essa demo usa dados em memória e um Mock Agent. É a forma mais segura de entender o projeto antes de conectar sistemas reais.

> A marca pública é **Maestro**. Alguns nomes de runtime ainda usam `symphony` por compatibilidade, incluindo o entrypoint de CLI e algumas variáveis de ambiente.

---

## Usando sistemas reais

Depois da demo local, você pode conectar um sistema de projeto real, um repositório Git e um coding agent.

### Exemplo: TAPD + GitHub + Codex

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

### Exemplo: Linear + GitHub + Codex

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

Antes de usar repositórios reais ou credenciais com muitos privilégios, leia:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## O que Maestro é, e o que não é

Maestro é:

- uma plataforma de execução de tarefas de engenharia que conecta sistemas de projeto, repositórios Git e coding agents;
- uma forma de executar AI agents a partir de tarefas reais de projeto;
- uma camada de workflow para coding, análise de requisitos, refinamento de tarefas, triage e sugestões de revisão;
- uma forma mais segura de testar, comparar e gerenciar diferentes coding agents.

Maestro não é:

- um novo modelo de linguagem;
- um substituto para Codex, Claude Code ou OpenCode;
- uma ferramenta para pular revisão, testes ou julgamento de release da equipe;
- um sistema ao qual você deve dar acesso ao repositório e depois deixar sem supervisão.

---

## Status do projeto

Maestro é software em estágio inicial e desenvolvimento ativo.

É adequado para:

- aprender como workflows de agents dirigidos por tarefas podem funcionar;
- rodar demos locais memory/mock;
- prototipar novas integrações;
- experimentar sistemas reais em ambientes controlados.

Tenha cuidado extra antes de:

- permitir que agents modifiquem repositórios reais ou façam push de branches;
- permitir que agents escrevam estados ou comentários em sistemas de projeto reais;
- usar credenciais com muitos privilégios ou tokens pessoais;
- compartilhar um mesmo ambiente de execução entre várias equipes;
- avançar para testes, release ou produção sem revisão humana.

Regra guia:

> **Automatize com ambição. Coloque gates com cuidado. Mantenha o rastro visível.**

---

## Saiba mais

- [Roadmap](./ROADMAP.pt-BR.md)
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
