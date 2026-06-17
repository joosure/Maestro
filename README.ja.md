# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

言語: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## AI Agent を実際のプロジェクトタスクから動かす。

Maestro は、**プロジェクト管理システム、Git リポジトリ、Coding Agent** をつなぎ、ひとつのエンジニアリングタスク実行フローにするプラットフォームです。

AI チャットを 1 つずつ監視する必要はありません。Maestro は Linear や TAPD などのプロジェクト管理システムから新規タスクや実行可能なタスクを読み取り、タスクごとに分離されたワークスペースを作成し、対象 Git リポジトリを準備し、適切な AI Agent を起動し、実行内容を記録して、結果をプロジェクト管理システムへ書き戻します。

Maestro は新しい Coding Agent ではありません。

Maestro が扱うのは、Agent が実用的になった後にチームが直面する問題です。タスクはどこから来るのか、コードはどこから来るのか、Agent はどこで動くのか、複数タスクをどう並列に扱うのか、何が変更されたのか、結果を信頼できるのか、失敗時にどう復旧・引き継ぎできるのか。

> **Symphony は、プロジェクトタスクで Agent を動かせることを示しました。Maestro は、そのパターンを運用可能なエンジニアリングプラットフォームにします。**

---

## ひとつの例

TAPD または Linear に次のようなタスクが追加されたとします。

> ユーザーが 2 つのクーポンを同時に使うと、チェックアウト画面でエラーが発生する。

Maestro を使うと、このタスクは追跡可能な Agent 実行になります。

1. Maestro が TAPD、Linear、または別のプロジェクト管理システムからタスクを同期または読み取ります。
2. Maestro が自分の実行環境内に、そのタスク専用の分離ワークスペースを作成します。
3. 設定に基づいて、対象 Git リポジトリをそのワークスペースへ clone / checkout します。
4. Maestro が Codex、Claude Code、OpenCode、または対応する Agent を起動し、タスク内容、リポジトリのコピー、利用可能なツールを渡します。
5. Agent はその独立したリポジトリコピーの中でコードを調査し、コード変更、分析結果、またはレビュー提案を準備します。
6. Maestro が diff、ログ、ツール呼び出し、実行サマリー、関連リンクを記録します。
7. Maestro が結果をプロジェクト管理システムへ書き戻し、チームはレビュー、修正、引き継ぎを行えます。

目的は、Agent を無制限に走らせることではありません。

> **プロジェクトタスクを、分離され、記録され、レビューでき、引き継げる Agent エンジニアリング実行に変えることです。**

分離ワークスペースには意味があります。各タスクが自分専用のディレクトリ、リポジトリコピー、ログ、一時ファイルを持つため、複数プロジェクト・複数タスクを並列に処理しても互いに汚染しません。失敗した実行も調査、掃除、再実行しやすくなります。

---

## なぜ Maestro が必要か

Coding Agent はコードを書く能力を高めています。しかしチームに必要なのは、単なるコード生成ではありません。

チームは次のことを知る必要があります。

- タスクはどのプロジェクト管理システムから来たのか。
- どの Git リポジトリとブランチに対応するのか。
- どの Agent が実行するべきか。
- Agent はどこで実行されるのか。
- 複数の実行をどう分離するのか。
- 何が変更されたのか。
- 人間がレビューできるのか。
- 失敗したらどうするのか。
- 実行の流れをどう理解するのか。

Maestro はこれらの問いを中心に作られています。

---

## Maestro でできること

### 1. バグタスクから Pull Request へ

TAPD または Linear にバグが入ります。Maestro はタスクを読み取り、分離ワークスペースを作成し、対象 Git リポジトリを準備し、Agent を起動します。Agent はコードを調査・変更し、Maestro は PR リンク、実行サマリー、未確認事項をタスクに書き戻します。

### 2. 実装前に要件を分析する

要件がまだ曖昧な場合、Maestro は Agent に影響範囲、リスク、受け入れ条件、確認すべき質問を出させることができます。

### 3. まだ開始できないタスクを整理する

必要な文脈が足りない場合、Agent に推測させるのではなく、前提、ブロッカー、確認事項を明らかにできます。

### 4. 新しいタスクをトリアージする

新しいタスクが入ったとき、Bug、要件、技術的負債、レビュー依頼などに分類し、優先度、リスク、次の状態を提案できます。

### 5. 複数の Coding Agent を比較する

同じ種類のタスクを Codex、Claude Code、OpenCode で実行し、出力、失敗理由、ログ、納品記録を比較できます。

### 6. 実アカウントなしでローカル体験する

`memory/no_repo/mock` フローを使えば、Linear、TAPD、GitHub、CNB、実 Agent に接続せずに Maestro の流れを理解できます。

---

## 現在の連携サポート

以下は Maestro の現在のコードでサポートされている連携と同梱テンプレートです。これらの外部システムが Maestro の中に組み込まれているという意味ではありません。Linear、TAPD、GitHub、CNB、Codex、Claude Code、OpenCode は外部システムまたは外部ツールであり、Maestro はそれらを接続・調整します。

プロジェクト管理システム:

- Linear
- TAPD
- Memory（ローカルテストとデモ用）

Agent:

- Codex
- Claude Code
- OpenCode
- Mock（ローカルテストとデモ用）

コードプラットフォーム:

- GitHub
- CNB
- Memory（ローカルテストとデモ用）

同梱 workflow template:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro は、さらに多くのプロジェクト管理システム、コードプラットフォーム、Agent、タスクフローへ拡張できるように設計されています。

---

## 仕組み

```text
プロジェクト管理システム内のタスク
   ↓
Maestro がタスクを読み取り/同期し、処理するか判断する
   ↓
Maestro が自分の実行環境に分離ワークスペースを作成する
   ↓
対象 Git リポジトリをそのワークスペース内に準備する
   ↓
AI Agent がタスク、リポジトリコピー、許可されたツールを使って実行される
   ↓
Agent がコード変更、分析結果、またはレビュー提案を出す
   ↓
Maestro が diff、ログ、ツール呼び出し、サマリー、リンクを記録する
   ↓
Maestro が結果をプロジェクト管理システムへ書き戻し、レビューや引き継ぎにつなげる
```

開発者向けには、Maestro は次の拡張ポイントとして理解できます。

- **プロジェクト管理システム**: タスクの入口。例: Linear、TAPD。
- **Git リポジトリとコードプラットフォーム**: clone 元、ブランチ、PR、レビュー、チェックの場所。
- **Agent**: 実行者。例: Codex、Claude Code、OpenCode。
- **ワークフロー**: バグ修正、要件分析、タスク整理、トリアージ、レビュー提案など。
- **ワークスペースと実行環境**: 各 Agent 実行がどこで動き、どう分離され、どう並列化されるか。
- **記録**: ログ、diff、タスクコメント、サマリーなどのレビュー可能な情報。

---

## クイックスタート

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

任意の dashboard を開きます。

```text
http://localhost:4000
```

このデモはメモリ上のデータと Mock Agent を使います。実システムへ接続する前に Maestro を理解するための最も安全な入口です。

> 公開ブランド名は **Maestro** です。一部のランタイム名は互換性のため `symphony` のままです。CLI エントリポイントや一部の環境変数も含まれます。

---

## 実システムに接続する

ローカルデモの後、実際のプロジェクト管理システム、Git リポジトリ、Coding Agent に接続できます。

### 例: TAPD + GitHub + Codex

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

### 例: Linear + GitHub + Codex

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

実リポジトリや高権限の認証情報を使う前に、次のドキュメントを読んでください。

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Maestro とは何か、何ではないか

Maestro は次のものです。

- プロジェクト管理システム、Git リポジトリ、Coding Agent をつなぐエンジニアリングタスク実行プラットフォーム。
- 実際のプロジェクトタスクから AI Agent を実行する方法。
- コーディング、要件分析、タスク整理、トリアージ、レビュー提案のためのワークフロー層。
- 複数の Coding Agent を安全に試し、比較し、管理する方法。

Maestro は次のものではありません。

- 新しい大規模言語モデル。
- Codex、Claude Code、OpenCode の代替品。
- チームのレビュー、テスト、リリース判断を飛ばすためのツール。
- リポジトリアクセスを与えたら放置してよい無人システム。

---

## プロジェクトの状態

Maestro は活発に開発中の初期段階のソフトウェアです。

適している用途：

- タスク駆動の Agent ワークフローを学ぶ。
- ローカル memory/mock デモを実行する。
- 新しい連携のプロトタイプを作る。
- 管理された環境で実システムを試す。

特に注意が必要な場面：

- Agent に実リポジトリの変更やブランチ push を許可する。
- Agent に実プロジェクト管理システムの状態やコメントを書き戻させる。
- 高権限の認証情報や個人 token を使う。
- 複数チームで同じ実行環境を共有する。
- 人間のレビューなしにテスト、リリース、本番工程へ進める。

基本原則：

> **大胆に自動化し、慎重にゲートを置き、実行の痕跡を見える状態に保つ。**

---

## さらに詳しく

- [Roadmap](./ROADMAP.ja.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Attribution

Maestro は [OpenAI Symphony](https://github.com/openai/symphony) の fork として始まりました。Symphony は、プロジェクトタスクが Coding Agent を駆動できることを示しました。Maestro はその考えを、実際のエンジニアリングワークフロー向けのより広いプラットフォームへ拡張します。

---

## License

Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements. Review `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, and `THIRD_PARTY_LICENSES.md` before using or distributing Maestro.
