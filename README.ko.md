# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

언어: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## AI Agent가 실제 프로젝트 작업에서 시작하도록 합니다.

Maestro는 **프로젝트 시스템, Git 저장소, Coding Agent**를 하나의 엔지니어링 작업 실행 흐름으로 연결하는 플랫폼입니다.

AI 채팅 창을 하나씩 지켜볼 필요가 없습니다. Maestro는 Linear, TAPD 같은 프로젝트 관리 시스템에서 새 작업이나 처리 가능한 작업을 읽고, 각 작업을 위한 격리된 작업 공간을 만들고, 대상 Git 저장소를 준비하고, 적절한 AI Agent를 실행하고, 실행 과정을 기록한 뒤 결과를 프로젝트 시스템에 다시 씁니다.

Maestro는 또 다른 Coding Agent가 아닙니다.

Maestro는 Agent가 유용해진 뒤 팀이 실제로 마주하는 문제를 다룹니다. 작업은 어디서 오는가, 코드는 어디서 오는가, Agent는 어디서 실행되는가, 여러 작업은 어떻게 병렬로 처리되는가, 무엇이 바뀌었는가, 결과를 신뢰할 수 있는가, 실패했을 때 어떻게 복구하거나 이어받을 수 있는가.

> **Symphony는 프로젝트 작업이 Agent를 구동할 수 있음을 보여주었습니다. Maestro는 그 패턴을 운영 가능한 엔지니어링 플랫폼으로 확장합니다.**

---

## 하나의 예시

TAPD 또는 Linear에 다음과 같은 작업이 새로 들어왔다고 가정해 보겠습니다.

> 사용자가 쿠폰 두 개를 동시에 적용하면 결제 페이지에서 오류가 발생한다.

Maestro를 사용하면 이 작업은 추적 가능한 Agent 실행이 됩니다.

1. Maestro가 TAPD, Linear 또는 다른 프로젝트 시스템에서 작업을 동기화하거나 읽습니다.
2. Maestro가 자체 실행 환경 안에 이 작업만을 위한 격리된 작업 공간을 만듭니다.
3. 설정에 따라 대상 Git 저장소를 그 작업 공간에 clone / checkout 합니다.
4. Maestro가 Codex, Claude Code, OpenCode 또는 지원되는 Agent를 실행하고 작업 내용, 저장소 복사본, 허용된 도구를 제공합니다.
5. Agent는 독립된 저장소 복사본 안에서 코드를 분석하고 코드 변경, 분석 결과 또는 리뷰 제안을 준비합니다.
6. Maestro는 diff, 로그, 도구 호출, 실행 요약, 관련 링크를 기록합니다.
7. Maestro는 결과를 프로젝트 시스템에 다시 써서 팀이 검토하거나 수정하거나 이어받을 수 있게 합니다.

목적은 Agent를 아무 통제 없이 실행하는 것이 아닙니다.

> **프로젝트 작업 하나를 격리되고, 기록되고, 검토 가능하며, 이어받을 수 있는 Agent 엔지니어링 실행으로 바꾸는 것입니다.**

격리된 작업 공간이 중요한 이유는 각 작업이 자기만의 디렉터리, 저장소 복사본, 로그, 임시 파일을 갖기 때문입니다. 여러 프로젝트와 여러 작업을 병렬로 처리해도 서로 오염시키지 않으며, 실패한 실행도 조사하고 정리하고 다시 실행하기 쉬워집니다.

---

## 왜 Maestro가 필요한가

Coding Agent는 점점 더 코드를 잘 작성합니다. 하지만 팀에 필요한 것은 단순한 코드 생성이 아닙니다.

팀은 다음 질문에 답할 수 있어야 합니다.

- 작업은 어떤 프로젝트 시스템에서 왔는가?
- 어떤 Git 저장소와 브랜치에 대응되는가?
- 어떤 Agent가 실행해야 하는가?
- Agent는 어디서 실행되는가?
- 여러 실행은 어떻게 서로 분리되는가?
- 무엇이 변경되었는가?
- 사람이 결과를 검토할 수 있는가?
- 실패하면 어떻게 되는가?
- 실행 중 무슨 일이 있었는지 어떻게 이해할 수 있는가?

Maestro는 이 질문들을 중심으로 설계되었습니다.

---

## Maestro로 할 수 있는 일

### 1. Bug 작업을 Pull Request로 연결

TAPD 또는 Linear에 Bug가 들어오면 Maestro가 작업을 읽고, 격리된 작업 공간을 만들고, 대상 Git 저장소를 준비하고, Agent를 실행합니다. Agent는 코드를 분석하고 변경하며, Maestro는 PR 링크, 실행 요약, 확인할 질문을 작업에 다시 씁니다.

### 2. 코딩 전에 요구사항 분석

요구사항이 아직 불명확하다면 Maestro가 Agent에게 영향 범위, 위험, 인수 조건, 확인 질문을 먼저 작성하게 할 수 있습니다.

### 3. 아직 시작할 수 없는 작업 정리

핵심 맥락이 부족한 작업에서는 Agent가 추측으로 코드를 쓰게 하는 대신, 가정, 차단 요소, 사람의 확인이 필요한 질문을 드러낼 수 있습니다.

### 4. 새 작업 분류

새 작업이 들어오면 Bug, 요구사항, 기술 부채, 리뷰 작업 등을 분류하고 우선순위, 위험, 다음 상태를 제안할 수 있습니다.

### 5. 여러 Coding Agent 비교

비슷한 작업을 Codex, Claude Code, OpenCode로 실행하고 결과, 실패 원인, 로그, 납품 기록을 비교할 수 있습니다.

### 6. 실제 계정 없이 로컬에서 체험

`memory/no_repo/mock` 흐름을 사용하면 Linear, TAPD, GitHub, CNB, 실제 Agent에 연결하지 않고 Maestro의 흐름을 이해할 수 있습니다.

---

## 현재 연동 지원

아래 항목은 Maestro 현재 코드에서 지원되는 연동과 제공 템플릿입니다. 이러한 외부 시스템이 Maestro 안에 내장되어 있다는 뜻은 아닙니다. Linear, TAPD, GitHub, CNB, Codex, Claude Code, OpenCode는 외부 시스템 또는 외부 도구이며, Maestro는 그것들을 연결하고 조율합니다.

프로젝트 시스템 어댑터:

- Linear
- TAPD
- Memory, 로컬 테스트와 데모용

Agent 어댑터:

- Codex
- Claude Code
- OpenCode
- Mock, 로컬 테스트와 데모용

코드 플랫폼 어댑터:

- GitHub
- CNB
- Memory, 로컬 테스트와 데모용

제공 workflow template:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro는 더 많은 프로젝트 시스템, 코드 플랫폼, Agent, 작업 흐름을 지원하도록 확장할 수 있게 설계되어 있습니다.

---

## 동작 방식

```text
프로젝트 시스템의 작업
   ↓
Maestro가 작업을 읽거나 동기화하고 처리 여부를 판단
   ↓
Maestro가 자체 실행 환경에 격리된 작업 공간을 생성
   ↓
대상 Git 저장소를 그 작업 공간 안에 준비
   ↓
AI Agent가 작업, 저장소 복사본, 허용된 도구를 가지고 실행
   ↓
Agent가 코드 변경, 분석 결과 또는 리뷰 제안을 생성
   ↓
Maestro가 diff, 로그, 도구 호출, 요약, 링크를 기록
   ↓
Maestro가 결과를 프로젝트 시스템에 다시 써서 검토 또는 인수인계로 연결
```

개발자 입장에서는 Maestro를 다음 확장 지점들로 이해할 수 있습니다.

- **프로젝트 시스템**: 작업이 들어오는 곳. 예: Linear, TAPD.
- **Git 저장소와 코드 플랫폼**: 코드를 clone하는 곳, 브랜치, PR, 리뷰, 체크가 발생하는 곳.
- **Agent**: 작업을 수행하는 주체. 예: Codex, Claude Code, OpenCode.
- **워크플로**: Bug 수정, 요구사항 분석, 작업 정리, 분류, 리뷰 제안 등.
- **작업 공간과 실행 환경**: 각 Agent 실행이 어디서 실행되고 어떻게 격리되며 어떻게 병렬화되는지.
- **기록**: 로그, diff, 작업 댓글, 요약 등 검토 가능한 정보.

---

## 빠른 시작

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

선택 사항인 dashboard를 엽니다.

```text
http://localhost:4000
```

이 데모는 메모리 데이터와 Mock Agent를 사용합니다. 실제 시스템에 연결하기 전에 프로젝트를 이해하는 가장 안전한 방법입니다.

> 공개 브랜드 이름은 **Maestro**입니다. 일부 런타임 이름은 호환성을 위해 아직 `symphony`를 사용합니다. CLI 진입점과 일부 환경 변수도 여기에 포함됩니다.

---

## 실제 시스템 연결

로컬 데모가 동작한 뒤에는 실제 프로젝트 시스템, Git 저장소, Coding Agent를 연결할 수 있습니다.

### 예시: TAPD + GitHub + Codex

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

### 예시: Linear + GitHub + Codex

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

실제 저장소나 높은 권한의 자격 증명을 사용하기 전에는 다음 문서를 읽어야 합니다.

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Maestro가 무엇이고, 무엇이 아닌가

Maestro는 다음과 같습니다.

- 프로젝트 시스템, Git 저장소, Coding Agent를 연결하는 엔지니어링 작업 실행 플랫폼.
- 실제 프로젝트 작업에서 AI Agent를 실행하는 방법.
- 코딩, 요구사항 분석, 작업 정리, 분류, 리뷰 제안을 위한 워크플로 계층.
- 여러 Coding Agent를 안전하게 시험하고 비교하고 관리하는 방법.

Maestro는 다음이 아닙니다.

- 새로운 대규모 언어 모델.
- Codex, Claude Code, OpenCode의 대체품.
- 팀의 리뷰, 테스트, 릴리스 판단을 건너뛰기 위한 도구.
- 저장소 접근 권한만 주고 방치해도 되는 무인 시스템.

---

## 프로젝트 상태

Maestro는 활발히 개발 중인 초기 단계 소프트웨어입니다.

적합한 용도:

- 작업 기반 Agent 워크플로 학습.
- 로컬 memory/mock 데모 실행.
- 새로운 연동 프로토타입 개발.
- 통제된 환경에서 실제 시스템 실험.

특히 주의해야 하는 경우:

- Agent가 실제 저장소를 수정하거나 브랜치를 push하도록 허용하는 경우.
- Agent가 실제 프로젝트 시스템의 상태나 댓글을 쓰도록 허용하는 경우.
- 높은 권한의 자격 증명이나 개인 token을 사용하는 경우.
- 여러 팀이 하나의 실행 환경을 공유하는 경우.
- 사람의 리뷰 없이 테스트, 릴리스, 운영 단계로 진행하는 경우.

기본 원칙:

> **과감하게 자동화하되, 신중하게 게이트를 두고, 실행 흔적을 보이게 유지한다.**

---

## 더 알아보기

- [Roadmap](./ROADMAP.ko.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Attribution

Maestro는 [OpenAI Symphony](https://github.com/openai/symphony)의 fork로 시작했습니다. Symphony는 프로젝트 작업이 Coding Agent를 구동할 수 있음을 보여주었습니다. Maestro는 그 아이디어를 실제 엔지니어링 워크플로를 위한 더 넓은 플랫폼으로 확장합니다.

---

## License

Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements. Review `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, and `THIRD_PARTY_LICENSES.md` before using or distributing Maestro.
