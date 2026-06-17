# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Языки: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Запускайте AI agents от реальных проектных задач.

Maestro соединяет **проектные системы, Git-репозитории и coding agents** в единый поток выполнения инженерных задач.

Вместо того чтобы вручную следить за отдельными AI-чатами, Maestro может читать новые или готовые к выполнению задачи из Linear, TAPD и других систем, создавать изолированную рабочую область для каждой задачи, подготавливать целевой Git-репозиторий, запускать подходящий AI Agent, записывать ход выполнения и возвращать результат обратно в проектную систему.

Maestro — это не очередной coding agent.

Он помогает командам отвечать на вопросы, которые появляются после того, как agents становятся полезными: откуда пришла задача, откуда берётся код, где запускается agent, как выполнять несколько задач параллельно, что изменилось, можно ли доверять результату и как команда может проверить, продолжить или восстановить выполнение.

> **Symphony показал, что проектные задачи могут управлять agents. Maestro превращает этот подход в пригодную для эксплуатации инженерную платформу.**

---

## Один пример

Представим, что в TAPD или Linear появилась новая задача:

> Страница checkout падает, когда пользователь применяет два купона.

С Maestro эта задача становится отслеживаемым запуском agent:

1. Maestro синхронизирует или читает задачу из TAPD, Linear или другой проектной системы.
2. Maestro создаёт изолированную рабочую область в своей собственной среде выполнения.
3. Maestro клонирует или checkout-ит целевой Git-репозиторий в эту рабочую область.
4. Maestro запускает Codex, Claude Code, OpenCode или другой поддерживаемый agent с задачей, копией репозитория и разрешёнными инструментами.
5. Agent анализирует копию репозитория и готовит изменение кода, результат анализа или предложение по review.
6. Maestro записывает diff, логи, вызовы инструментов, summary и связанные ссылки.
7. Maestro возвращает результат в проектную систему, чтобы команда могла проверить, продолжить или взять задачу на себя.

Смысл не в том, чтобы agent работал вслепую. Смысл в другом:

> **Проектная задача превращается в изолированный, записанный, проверяемый и передаваемый engineering run.**

Изолированная рабочая область важна: у каждой задачи есть свой каталог, своя копия репозитория, свои логи и временные файлы. Несколько проектов и задач могут выполняться параллельно, не мешая друг другу. Если запуск не удался, его проще изучить, очистить и повторить.

---

## Почему это важно

Coding agents всё лучше пишут код. Но командам нужно больше, чем генерация кода.

Им нужны практические ответы:

- Из какой проектной системы пришла задача?
- Какому Git-репозиторию и ветке она соответствует?
- Какой agent должен её выполнять?
- Где запускается agent?
- Как несколько запусков остаются изолированными?
- Что изменилось?
- Может ли человек проверить результат?
- Что происходит при сбое?
- Как команда понимает, что произошло?

Maestro построен вокруг этих вопросов.

---

## Что можно делать с Maestro

### 1. Превратить bug-задачу в Pull Request

Bug появляется в TAPD или Linear. Maestro читает задачу, создаёт изолированную рабочую область, подготавливает целевой Git-репозиторий, запускает agent, позволяет agent проанализировать и изменить код, а затем записывает ссылку на PR, summary и открытые вопросы обратно в задачу.

### 2. Анализировать требование до написания кода

Если требование ещё не ясно, Maestro может попросить agent подготовить scope, риски, acceptance criteria и вопросы для уточнения до начала реализации.

### 3. Уточнить задачу, которая ещё не готова к старту

Если не хватает контекста, Maestro может выявить предположения, блокеры и вопросы вместо того, чтобы позволять agent угадывать.

### 4. Триажить входящие задачи

Maestro может помогать классифицировать новые задачи, предлагать приоритет, выявлять риски и рекомендовать следующий статус.

### 5. Сравнивать разных coding agents

Похожие задачи можно запускать через Codex, Claude Code или OpenCode и сравнивать результаты, причины ошибок, логи и записи доставки.

### 6. Попробовать локально без реальных аккаунтов

Используйте локальный поток `memory/no_repo/mock`, чтобы понять Maestro без подключения Linear, TAPD, GitHub, CNB, Codex, Claude Code или OpenCode.

---

## Текущие поддерживаемые интеграции

Перечисленное ниже — это **поддерживаемые интеграции и поставляемые шаблоны**, а не системы, встроенные внутрь Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code и OpenCode остаются внешними системами или инструментами. Maestro соединяет и оркестрирует их.

Адаптеры проектных систем:

- Linear
- TAPD
- Memory, для локальных тестов и демо

Адаптеры Agent:

- Codex
- Claude Code
- OpenCode
- Mock, для локальных тестов и демо

Адаптеры кодовых платформ:

- GitHub
- CNB
- Memory, для локальных тестов и демо

Поставляемые workflow templates:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro спроектирован так, чтобы расти вместе с новыми проектными системами, кодовыми платформами, agents и workflow templates.

---

## Как это работает

```text
Задача в проектной системе
   ↓
Maestro читает/синхронизирует задачу и решает, обрабатывать ли её
   ↓
Maestro создаёт изолированную рабочую область в своей среде выполнения
   ↓
Целевой Git-репозиторий подготавливается внутри этой рабочей области
   ↓
AI Agent запускается с задачей, копией репозитория и разрешёнными инструментами
   ↓
Agent создаёт изменение кода, результат анализа или предложение по review
   ↓
Maestro записывает diffs, логи, вызовы инструментов, summaries и ссылки
   ↓
Maestro возвращает результат в проектную систему для review или передачи
```

Для разработчиков этот же поток можно понимать как набор расширяемых частей:

- **Проектные системы**: откуда приходят задачи, например Linear или TAPD.
- **Git-репозитории и кодовые платформы**: откуда клонируется код и где происходят branches, PRs, reviews и checks.
- **Agents**: кто выполняет работу, например Codex, Claude Code или OpenCode.
- **Workflows**: какая работа выполняется: исправление bugs, анализ требований, уточнение задач, triage или предложения по review.
- **Рабочие области и runtime**: где происходит каждый запуск, как он изолирован и как запуски идут параллельно.
- **Записи**: логи, diffs, комментарии к задачам, summaries и другая проверяемая информация.

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

Откройте опциональный dashboard:

```text
http://localhost:4000
```

Это демо использует данные в памяти и Mock Agent. Это самый безопасный способ понять проект до подключения реальных систем.

> Публичный бренд — **Maestro**. Некоторые runtime-имена всё ещё используют `symphony` для совместимости, включая CLI entrypoint и часть переменных окружения.

---

## Использование реальных систем

После локального демо можно подключить реальную проектную систему, Git-репозиторий и coding agent.

### Пример: TAPD + GitHub + Codex

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

### Пример: Linear + GitHub + Codex

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

Перед использованием реальных репозиториев или высокопривилегированных credentials прочитайте:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Что такое Maestro, и чем он не является

Maestro — это:

- платформа выполнения инженерных задач, соединяющая проектные системы, Git-репозитории и coding agents;
- способ запускать AI agents от реальных проектных задач;
- workflow-слой для coding, анализа требований, уточнения задач, triage и предложений по review;
- более безопасный способ тестировать, сравнивать и управлять разными coding agents.

Maestro — это не:

- новая большая языковая модель;
- замена Codex, Claude Code или OpenCode;
- инструмент для обхода review, тестов или release-решений команды;
- система, которой стоит выдать доступ к репозиторию и оставить без присмотра.

---

## Статус проекта

Maestro — раннее ПО в активной разработке.

Подходит для:

- изучения task-driven agent workflows;
- запуска локальных memory/mock demos;
- прототипирования новых интеграций;
- экспериментов с реальными системами в контролируемой среде.

Особая осторожность нужна перед тем, как:

- разрешить agents менять реальные репозитории или push-ить branches;
- разрешить agents записывать статусы или комментарии в реальные проектные системы;
- использовать высокопривилегированные credentials или personal tokens;
- делить одну runtime-среду между несколькими командами;
- переходить к тестам, release или production без human review.

Основное правило:

> **Автоматизируйте смело. Ставьте gates осторожно. Держите след выполнения видимым.**

---

## Подробнее

- [Roadmap](./ROADMAP.ru.md)
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
