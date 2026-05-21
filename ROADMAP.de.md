# Maestro Roadmap

Sprachen: [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [Deutsch](./ROADMAP.de.md) · [More](./LANGUAGES.md)

## Ziel

Maestro hat ein einfaches Ziel:

> **AI Agents für echte Engineering-Teams einfacher, sicherer und verlässlicher nutzbar machen.**

Viele Coding Agents können bereits Code schreiben. Teams brauchen mehr als Codegenerierung:

- Arbeit sollte aus echten Systemen wie TAPD, Linear und zukünftigen Plattformen kommen;
- Code sollte aus einem explizit konfigurierten Git-Repository und Branch kommen;
- jeder Lauf braucht eine isolierte Arbeitsumgebung, damit Aufgaben sich nicht gegenseitig stören;
- Menschen sollen verstehen, was der Agent getan hat, was geändert wurde und warum etwas fehlgeschlagen ist;
- risikoreiche Schritte sollen reviewbar bleiben;
- Teams sollen die Nutzung schrittweise ausbauen können, statt am ersten Tag alle Rechte zu öffnen.

Diese Roadmap ist nach Nutzerwert organisiert, nicht nach internen Modulnamen.

---

## Kurzfristig: Maestro leichter ausprobieren

Ein neuer Nutzer soll Maestro verstehen und ausführen können, ohne zuerst die gesamte Architektur zu lernen.

Geplante Arbeit:

- einfachere lokale Demo;
- klarere Quick-Start-Anleitung;
- Screenshots, GIFs oder kurze Videos;
- Beispielaufgaben, die den vollständigen Ablauf zeigen;
- klare Erklärung, warum isolierte Arbeitsumgebungen wichtig sind: Parallelität, Isolation, Bereinigung und Reviewbarkeit;
- Erklärung verbleibender `symphony`-Kompatibilitätsnamen;
- klarer Weg von der lokalen Demo zu einer echten Projektkonfiguration.

Szenarien, die leichter demonstrierbar werden sollen:

- TAPD-Aufgabe zu GitHub Pull Request;
- Linear-Aufgabe zu GitHub Pull Request;
- Anforderungsanalyse vor dem Coding;
- Triage eingehender Arbeit;
- Reviewer-Vorschläge;
- Vergleich von Codex, Claude Code und OpenCode bei ähnlichen Aufgaben.

Erfolg bedeutet, dass neue Leser in wenigen Minuten beantworten können:

> „Was macht Maestro, und warum könnte mein Team es brauchen?“

---

## Als Nächstes: Agents mit echten Projekt-Workflows verbinden

Maestro soll Agents aus den Systemen arbeiten lassen, die Teams bereits nutzen, statt eine neue Aufgabenwarteschlange zu erzwingen.

Geplante Arbeit:

- aktuelle TAPD- und Linear-Flows verbessern;
- Aufgabenstatus, Kommentare, Links und Ergebnisse verständlicher machen;
- Workflow-Templates leichter auffindbar, kopierbar und anpassbar machen;
- häufige Aufgaben unterstützen: Bugfixes, kleine Features, Anforderungsanalyse, Aufgabenverfeinerung, Triage und Review-Vorschläge;
- aktuellen Integrationssupport klar von zukünftigen Erweiterungszielen trennen;
- weitere Integrationen wie Jira, GitHub Issues, GitLab, Gitea, Bitbucket und Feishu Project vorbereiten.

Erfolg bedeutet, dass Teams aus ihrem bestehenden Projektworkflow starten können, ohne ihr Arbeitsmanagement nur für Agents zu ändern.

---

## Mittelfristig: Agent-Arbeit vertrauenswürdiger machen

Ein Team sollte einem Lauf nicht nur vertrauen, weil der Agent „fertig“ sagt.

Geplante Arbeit:

- klarere Laufhistorie;
- leichter lesbare Zusammenfassungen;
- bessere Verknüpfung zwischen Aufgaben, Git-Änderungen, Logs und Review-Material;
- klarere Fehlergründe;
- bessere Log-Redaction;
- nützlicheres dashboard;
- sichtbare Checkpoints vor dem Schreiben in echte Projektsysteme, dem Pushen von Branches oder dem Erstellen von PRs;
- klare Trennung zwischen lokaler Demo, vertrauenswürdiger Evaluation, Team-Pilot und Produktivbetrieb.

Erfolg bedeutet, dass Reviewer beantworten können:

- Was hat der Agent getan?
- Von welcher Aufgabe und welchem Git-Repository aus hat er gearbeitet?
- Was wurde geändert?
- Warum hat er gestoppt?
- Was braucht noch menschliche Bestätigung?
- Ist es sicher, fortzufahren?

---

## Langfristig: Teams beim skalierenden Einsatz von Agents helfen

Eine Demo mit einem Agent ist nützlich. Teamweite Nutzung braucht stärkeren Betrieb.

Geplante Arbeit:

- mehrere Aufgaben sicher gleichzeitig ausführen;
- getrennte Workspaces und Aufzeichnungen für verschiedene Projekte und Aufgaben halten;
- je nach Aufgabentyp unterschiedliche Agents wählen;
- Accounts, Zugangsdaten, Quoten und Kosten klarer verwalten;
- Team-Laufzeitumgebungen verbessern;
- Retry und Recovery verbessern;
- klarere menschliche Freigabepunkte unterstützen;
- Teams helfen, die echte Wirksamkeit verschiedener Agents und Workflows zu vergleichen.

Erfolg bedeutet, dass Teams die Agent-Nutzung schrittweise ausbauen können, während Sicherheit, Kosten und Qualität unter Kontrolle bleiben.

---

## Dokumentation und Community

Maestro sollte verständlich sein, bevor es mächtig wirkt.

Geplante Arbeit:

- Haupt-README kurz und beispielorientiert halten;
- tiefe technische Details in separate Dokumente verschieben;
- English und Simplified Chinese aktiv pflegen;
- weitere Übersetzungen verfügbar halten und Community-Verbesserungen willkommen heißen;
- Contribution-Guides für Projektsysteme, Agents, Code-Plattformen und Workflow-Templates ergänzen;
- mehr Beispiele aus echten Engineering-Szenarien veröffentlichen.

Erfolg bedeutet, dass Mitwirkende einen nützlichen Einstieg finden, ohne zuerst die gesamte Codebasis zu lesen.

---

## Derzeit keine Ziele

Maestro soll Teams nicht helfen, Reviews, Tests oder Release-Entscheidungen zu umgehen.

Wichtiger ist:

- Agents mit echten Aufgaben verbinden;
- Codequelle und Aufgabenquelle sichtbar machen;
- den Ausführungsprozess nachvollziehbar halten;
- bei risikoreichen Schritten menschliche Kontrolle behalten;
- nützliche Laufaufzeichnungen erhalten;
- Automatisierung nur mit wachsendem Vertrauen ausbauen.

Automatisierung sollte mit Evidenz wachsen, nicht mit Wunschdenken.

---

## Aktueller Fokus

Der aktuelle Fokus liegt darauf, Maestro verständlicher, leichter testbar und sicherer evaluierbar zu machen:

1. öffentliches README vereinfachen;
2. Roadmap in klarer Sprache ergänzen;
3. Anleitung für lokale Demo verbessern;
4. aktuellen Integrationssupport beschreiben, ohne externe Systeme als „eingebaut“ zu bezeichnen;
5. erklären, warum isolierte Workspaces wichtig sind;
6. Beispiele für TAPD, Linear, GitHub, CNB und echte Agent-Kombinationen ergänzen;
7. technische Details verfügbar halten, ohne neue Leser damit zu überladen.

---

## Mitwirken

Nützliche Beiträge:

- bessere Beispiele;
- klarere Dokumentation;
- sicherere Workflow-Templates;
- neue Projektsystem-Integrationen;
- neue Coding-Agent-Integrationen;
- neue Code-Plattform-Integrationen;
- dashboard-Verbesserungen;
- Testabdeckung für echte Workflows;
- Übersetzungsreview durch Muttersprachler.

Beginne mit dem lokalen memory/mock-Flow und gehe danach schrittweise zu echten Systemen über.
