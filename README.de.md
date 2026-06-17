# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Sprachen: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Lass AI Agents aus echten Projektaufgaben heraus arbeiten.

Maestro verbindet **Projektsysteme, Git-Repositories und Coding Agents** zu einem gemeinsamen Ausführungsfluss für Engineering-Aufgaben.

Statt einzelne AI-Chats manuell zu überwachen, kann Maestro neue oder bereite Aufgaben aus Systemen wie Linear oder TAPD lesen, für jede Aufgabe eine isolierte Arbeitsumgebung erstellen, das Ziel-Git-Repository vorbereiten, den passenden AI Agent starten, den Ablauf protokollieren und das Ergebnis in das Projektsystem zurückschreiben.

Maestro ist kein weiterer Coding Agent.

Maestro hilft Teams bei den Fragen, die entstehen, wenn Agents praktisch nützlich werden: Woher kommt die Aufgabe? Woher kommt der Code? Wo läuft der Agent? Wie laufen mehrere Aufgaben parallel? Was wurde geändert? Ist das Ergebnis nachvollziehbar? Wie kann das Team prüfen, übernehmen oder einen Lauf wiederherstellen?

> **Symphony hat gezeigt, dass Projektaufgaben Agents steuern können. Maestro macht daraus eine betreibbare Engineering-Plattform.**

---

## Ein Beispiel

Angenommen, in TAPD oder Linear erscheint eine neue Aufgabe:

> Die Checkout-Seite schlägt fehl, wenn ein Nutzer zwei Gutscheine anwendet.

Mit Maestro wird daraus ein nachvollziehbarer Agent-Lauf:

1. Maestro synchronisiert oder liest die Aufgabe aus TAPD, Linear oder einem anderen Projektsystem.
2. Maestro erstellt in seiner eigenen Laufzeitumgebung eine isolierte Arbeitsumgebung für diese Aufgabe.
3. Maestro clont oder checkt das Ziel-Git-Repository in diese Arbeitsumgebung aus.
4. Maestro startet Codex, Claude Code, OpenCode oder einen anderen unterstützten Agent mit Aufgabe, Repository-Kopie und erlaubten Werkzeugen.
5. Der Agent analysiert die Repository-Kopie und bereitet eine Codeänderung, ein Analyseergebnis oder einen Review-Vorschlag vor.
6. Maestro zeichnet diff, Logs, Tool-Aufrufe, Zusammenfassung und zugehörige Links auf.
7. Maestro schreibt das Ergebnis in das Projektsystem zurück, damit das Team prüfen, fortsetzen oder übernehmen kann.

Es geht nicht darum, einen Agent blind laufen zu lassen. Der Kern ist:

> **Eine Projektaufgabe wird zu einem isolierten, aufgezeichneten, reviewbaren und übernehmbaren Agent-Engineering-Lauf.**

Die isolierte Arbeitsumgebung ist wichtig: Jede Aufgabe hat ein eigenes Verzeichnis, eine eigene Repository-Kopie, eigene Logs und temporäre Dateien. Dadurch können mehrere Projekte und Aufgaben parallel laufen, ohne sich gegenseitig zu beeinflussen. Fehlgeschlagene Läufe lassen sich leichter untersuchen, bereinigen und erneut starten.

---

## Warum das wichtig ist

Coding Agents werden immer besser darin, Code zu schreiben. Teams brauchen aber mehr als Codegenerierung.

Sie brauchen praktische Antworten:

- Aus welchem Projektsystem kommt die Aufgabe?
- Welchem Git-Repository und Branch ist sie zugeordnet?
- Welcher Agent soll laufen?
- Wo läuft der Agent?
- Wie bleiben mehrere Läufe voneinander getrennt?
- Was wurde geändert?
- Können Menschen das Ergebnis prüfen?
- Was passiert bei einem Fehler?
- Wie versteht das Team den Ablauf?

Maestro ist um diese Fragen herum gebaut.

---

## Was du mit Maestro tun kannst

### 1. Aus einer Bug-Aufgabe einen Pull Request machen

Ein Bug erscheint in TAPD oder Linear. Maestro liest die Aufgabe, erstellt eine isolierte Arbeitsumgebung, bereitet das Ziel-Git-Repository vor, startet einen Agent, lässt den Agent Code analysieren und ändern und schreibt PR-Link, Zusammenfassung und offene Fragen zurück in die Aufgabe.

### 2. Anforderungen vor der Umsetzung analysieren

Wenn eine Anforderung noch unklar ist, kann Maestro einen Agent zuerst Umfang, Risiken, Akzeptanzkriterien und Klärungsfragen erstellen lassen.

### 3. Eine Aufgabe klären, die noch nicht startbereit ist

Wenn Kontext fehlt, kann Maestro Annahmen, Blocker und Fragen sichtbar machen, statt den Agent raten zu lassen.

### 4. Eingehende Arbeit triagieren

Maestro kann neue Aufgaben klassifizieren, Priorität vorschlagen, Risiken erkennen und den nächsten Status empfehlen.

### 5. Verschiedene Coding Agents vergleichen

Ähnliche Aufgaben können mit Codex, Claude Code oder OpenCode laufen. Das Team kann Ergebnisse, Fehlerarten, Logs und Liefernachweise vergleichen.

### 6. Lokal ohne echte Konten ausprobieren

Mit dem lokalen `memory/no_repo/mock`-Flow lässt sich Maestro verstehen, ohne Linear, TAPD, GitHub, CNB, Codex, Claude Code oder OpenCode zu verbinden.

---

## Aktuell unterstützte Integrationen

Die folgenden Systeme sind **unterstützte Integrationen und mitgelieferte Templates**, keine in Maestro eingebauten Systeme. Linear, TAPD, GitHub, CNB, Codex, Claude Code und OpenCode bleiben externe Systeme oder Werkzeuge. Maestro verbindet und orchestriert sie.

Adapter für Projektsysteme:

- Linear
- TAPD
- Memory, für lokale Tests und Demos

Agent-Adapter:

- Codex
- Claude Code
- OpenCode
- Mock, für lokale Tests und Demos

Adapter für Code-Plattformen:

- GitHub
- CNB
- Memory, für lokale Tests und Demos

Mitgelieferte Workflow-Templates:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro ist darauf ausgelegt, mit weiteren Projektsystemen, Code-Plattformen, Agents und Workflow-Templates zu wachsen.

---

## Wie es funktioniert

```text
Aufgabe in einem Projektsystem
   ↓
Maestro liest/synchronisiert die Aufgabe und entscheidet, ob sie bearbeitet wird
   ↓
Maestro erstellt eine isolierte Arbeitsumgebung in seiner eigenen Laufzeitumgebung
   ↓
Das Ziel-Git-Repository wird in dieser Arbeitsumgebung vorbereitet
   ↓
Ein AI Agent läuft mit Aufgabe, Repository-Kopie und erlaubten Werkzeugen
   ↓
Der Agent erzeugt Codeänderung, Analyseergebnis oder Review-Vorschlag
   ↓
Maestro zeichnet diffs, Logs, Tool-Aufrufe, Zusammenfassungen und Links auf
   ↓
Maestro schreibt das Ergebnis zur Prüfung oder Übergabe in das Projektsystem zurück
```

Für Entwickler lässt sich derselbe Ablauf über einige Erweiterungspunkte verstehen:

- **Projektsysteme**: Wo Aufgaben herkommen, etwa Linear oder TAPD.
- **Git-Repositories und Code-Plattformen**: Wo Code geclont wird und wo Branches, PRs, Reviews und Checks passieren.
- **Agents**: Wer die Arbeit ausführt, etwa Codex, Claude Code oder OpenCode.
- **Workflows**: Welche Art von Arbeit passiert: Bugs beheben, Anforderungen analysieren, Aufgaben verfeinern, Arbeit triagieren oder Reviews vorschlagen.
- **Arbeitsumgebungen und Runtimes**: Wo jeder Agent-Lauf stattfindet, wie er isoliert wird und wie Läufe parallel stattfinden können.
- **Aufzeichnungen**: Logs, diffs, Aufgabenkommentare, Zusammenfassungen und andere reviewbare Informationen.

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

Optionales dashboard öffnen:

```text
http://localhost:4000
```

Diese Demo nutzt Speicherdaten und einen Mock Agent. Sie ist der sicherste Einstieg, bevor echte Systeme verbunden werden.

> Die öffentliche Marke ist **Maestro**. Einige Laufzeitnamen verwenden aus Kompatibilitätsgründen weiterhin `symphony`, darunter der CLI-Einstieg und einige Umgebungsvariablen.

---

## Echte Systeme verwenden

Nach der lokalen Demo kannst du ein echtes Projektsystem, ein Git-Repository und einen Coding Agent verbinden.

### Beispiel: TAPD + GitHub + Codex

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

### Beispiel: Linear + GitHub + Codex

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

Lies vor echten Repositories oder hochberechtigten Zugangsdaten:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Was Maestro ist — und was nicht

Maestro ist:

- eine Plattform zur Ausführung von Engineering-Aufgaben, die Projektsysteme, Git-Repositories und Coding Agents verbindet;
- eine Möglichkeit, AI Agents aus echten Projektaufgaben heraus auszuführen;
- eine Workflow-Schicht für Coding, Anforderungsanalyse, Aufgabenverfeinerung, Triage und Review-Vorschläge;
- ein sichererer Weg, verschiedene Coding Agents zu testen, zu vergleichen und zu verwalten.

Maestro ist nicht:

- ein neues großes Sprachmodell;
- ein Ersatz für Codex, Claude Code oder OpenCode;
- ein Werkzeug, um Team-Reviews, Tests oder Release-Entscheidungen zu umgehen;
- ein System, dem man Repository-Zugriff gibt und das man dann unbeaufsichtigt lässt.

---

## Projektstatus

Maestro ist frühe Software in aktiver Entwicklung.

Geeignet für:

- Lernen, wie aufgabengetriebene Agent-Workflows funktionieren können;
- lokale memory/mock-Demos;
- Prototypen für neue Integrationen;
- Experimente mit echten Systemen in kontrollierten Umgebungen.

Besondere Vorsicht vor:

- Agents, die echte Repositories ändern oder Branches pushen dürfen;
- Agents, die Status oder Kommentare in echte Projektsysteme schreiben dürfen;
- hochberechtigten Zugangsdaten oder persönlichen Tokens;
- einer gemeinsamen Laufzeitumgebung für mehrere Teams;
- Test-, Release- oder Produktionsschritten ohne menschliches Review.

Leitregel:

> **Mutig automatisieren. Gates sorgfältig setzen. Die Spur sichtbar halten.**

---

## Mehr erfahren

- [Roadmap](./ROADMAP.de.md)
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
