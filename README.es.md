# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Idiomas: [English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Haz que los AI agents trabajen desde tareas reales de proyecto.

Maestro conecta **sistemas de proyecto, repositorios Git y coding agents** en un solo flujo de ejecución de tareas de ingeniería.

En vez de vigilar una conversación de IA a la vez, Maestro puede leer tareas nuevas o listas para ejecutarse desde sistemas como Linear o TAPD, crear un espacio de trabajo aislado para cada tarea, preparar el repositorio Git objetivo, arrancar el AI agent adecuado, registrar lo ocurrido y escribir el resultado de vuelta en el sistema de proyecto.

Maestro no es otro coding agent.

Ayuda a los equipos a responder las preguntas que aparecen cuando los agents ya empiezan a ser útiles: de dónde viene la tarea, de dónde viene el código, dónde corre el agent, cómo ejecutar varias tareas en paralelo, qué cambió, si el resultado es confiable y cómo revisar o recuperar la ejecución.

> **Symphony demostró que las tareas de proyecto pueden dirigir agents. Maestro convierte ese patrón en una plataforma de ingeniería operable.**

---

## Un ejemplo

Imagina que aparece una tarea nueva en TAPD o Linear:

> La página de checkout falla cuando un usuario aplica dos cupones.

Con Maestro, esa tarea puede convertirse en una ejecución visible de agent:

1. Maestro sincroniza o lee la tarea desde TAPD, Linear u otro sistema de proyecto.
2. Maestro crea un espacio de trabajo aislado en su propio entorno de ejecución.
3. Maestro clona o hace checkout del repositorio Git objetivo dentro de ese espacio.
4. Maestro inicia Codex, Claude Code, OpenCode u otro agent soportado con la tarea, la copia del repositorio y las herramientas permitidas.
5. El agent analiza la copia del repositorio y prepara un cambio de código, un resultado de análisis o una sugerencia de revisión.
6. Maestro registra diff, logs, llamadas a herramientas, resumen y enlaces relacionados.
7. Maestro escribe el resultado de vuelta en el sistema de proyecto para que el equipo pueda revisar, continuar o tomar el control.

La idea no es dejar que un agent corra a ciegas. La idea es esta:

> **Una tarea de proyecto se convierte en una ejecución de ingeniería aislada, registrada, revisable y transferible.**

El espacio de trabajo aislado importa porque cada tarea tiene su propio directorio, copia del repositorio, logs y archivos temporales. Así varios proyectos y tareas pueden ejecutarse en paralelo sin contaminarse entre sí; si algo falla, es más fácil inspeccionar, limpiar y reintentar.

---

## Por qué importa

Los coding agents cada vez escriben mejor código. Pero los equipos necesitan más que generación de código.

Necesitan respuestas prácticas:

- ¿De qué sistema de proyecto viene la tarea?
- ¿A qué repositorio Git y rama corresponde?
- ¿Qué agent debería ejecutarla?
- ¿Dónde corre el agent?
- ¿Cómo se mantienen aisladas varias ejecuciones?
- ¿Qué cambió?
- ¿Puede una persona revisar el resultado?
- ¿Qué pasa si falla?
- ¿Cómo entiende el equipo lo ocurrido?

Maestro está construido alrededor de esas preguntas.

---

## Qué puedes hacer con Maestro

### 1. Convertir una tarea de bug en un Pull Request

Aparece un bug en TAPD o Linear. Maestro lee la tarea, crea un espacio de trabajo aislado, prepara el repositorio Git objetivo, inicia un agent, deja que el agent analice y cambie el código, y escribe el enlace del PR, el resumen y las preguntas abiertas de vuelta en la tarea.

### 2. Analizar un requisito antes de programar

Si un requisito aún no está claro, Maestro puede pedir a un agent que produzca alcance, riesgos, criterios de aceptación y preguntas de aclaración antes de empezar la implementación.

### 3. Refinar una tarea que todavía no puede empezar

Si falta contexto, Maestro puede sacar a la luz supuestos, bloqueos y preguntas en vez de dejar que el agent adivine.

### 4. Clasificar trabajo entrante

Maestro puede ayudar a clasificar nuevas tareas, sugerir prioridad, identificar riesgos y recomendar el siguiente estado.

### 5. Comparar diferentes coding agents

Puedes ejecutar tareas similares con Codex, Claude Code u OpenCode y comparar resultados, fallos, logs y registros de entrega.

### 6. Probar el flujo localmente sin cuentas reales

Usa el flujo local `memory/no_repo/mock` para entender Maestro sin conectar Linear, TAPD, GitHub, CNB, Codex, Claude Code u OpenCode.

---

## Integraciones soportadas actualmente

Los sistemas siguientes son **integraciones soportadas y plantillas incluidas**, no sistemas embebidos dentro de Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code y OpenCode siguen siendo sistemas o herramientas externas. Maestro los conecta y los coordina.

Adaptadores de sistema de proyecto:

- Linear
- TAPD
- Memory, para pruebas y demos locales

Adaptadores de agent:

- Codex
- Claude Code
- OpenCode
- Mock, para pruebas y demos locales

Adaptadores de plataforma de código:

- GitHub
- CNB
- Memory, para pruebas y demos locales

Plantillas de workflow incluidas:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro está diseñado para crecer con más sistemas de proyecto, plataformas de código, agents y plantillas de workflow.

---

## Cómo funciona

```text
Tarea en un sistema de proyecto
   ↓
Maestro lee/sincroniza la tarea y decide si debe manejarla
   ↓
Maestro crea un espacio de trabajo aislado en su propio entorno de ejecución
   ↓
El repositorio Git objetivo se prepara dentro de ese espacio
   ↓
Un AI agent corre con la tarea, la copia del repositorio y las herramientas permitidas
   ↓
El agent produce un cambio de código, resultado de análisis o sugerencia de revisión
   ↓
Maestro registra diffs, logs, llamadas a herramientas, resúmenes y enlaces
   ↓
Maestro escribe el resultado de vuelta en el sistema de proyecto para revisión o traspaso
```

Para desarrolladores, el mismo flujo se organiza alrededor de algunos puntos extensibles:

- **Sistemas de proyecto**: de dónde vienen las tareas, como Linear o TAPD.
- **Repositorios Git y plataformas de código**: de dónde se clona el código y dónde ocurren ramas, PRs, revisiones y checks.
- **Agents**: quién hace el trabajo, como Codex, Claude Code u OpenCode.
- **Workflows**: qué tipo de trabajo se hace: corregir bugs, analizar requisitos, refinar tareas, clasificar trabajo o sugerir revisiones.
- **Espacios de trabajo y entornos de ejecución**: dónde ocurre cada ejecución, cómo se aísla y cómo se ejecuta en paralelo.
- **Registros**: logs, diffs, comentarios de tareas, resúmenes y otra información revisable.

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

Abre el dashboard opcional:

```text
http://localhost:4000
```

Esta demo usa datos en memoria y un Mock Agent. Es la forma más segura de entender el proyecto antes de conectar sistemas reales.

> La marca pública es **Maestro**. Algunos nombres de runtime todavía usan `symphony` por compatibilidad, incluido el punto de entrada CLI y algunas variables de entorno.

---

## Usar sistemas reales

Después de la demo local, puedes conectar un sistema de proyecto real, un repositorio Git y un coding agent.

### Ejemplo: TAPD + GitHub + Codex

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

### Ejemplo: Linear + GitHub + Codex

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

Antes de usar repositorios reales o credenciales con muchos permisos, lee:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Qué es Maestro, y qué no es

Maestro es:

- una plataforma de ejecución de tareas de ingeniería que conecta sistemas de proyecto, repositorios Git y coding agents;
- una forma de ejecutar AI agents desde tareas reales de proyecto;
- una capa de workflow para coding, análisis de requisitos, refinamiento de tareas, triage y sugerencias de revisión;
- una forma más segura de probar, comparar y gestionar distintos coding agents.

Maestro no es:

- un nuevo modelo de lenguaje;
- un reemplazo de Codex, Claude Code u OpenCode;
- una herramienta para saltarse la revisión, las pruebas o el criterio de release del equipo;
- un sistema al que debas dar acceso al repositorio y luego dejar sin supervisión.

---

## Estado del proyecto

Maestro es software en etapa temprana y en desarrollo activo.

Es adecuado para:

- aprender cómo pueden funcionar workflows de agents dirigidos por tareas;
- ejecutar demos locales memory/mock;
- prototipar nuevas integraciones;
- experimentar con sistemas reales en entornos controlados.

Ten especial cuidado antes de:

- permitir que agents modifiquen repositorios reales o empujen ramas;
- permitir que agents escriban estados o comentarios en sistemas de proyecto reales;
- usar credenciales con muchos permisos o tokens personales;
- compartir un mismo entorno de ejecución entre varios equipos;
- avanzar a pruebas, release o producción sin revisión humana.

Regla guía:

> **Automatiza con ambición. Pon gates con cuidado. Mantén visible el rastro.**

---

## Más información

- [Roadmap](./ROADMAP.es.md)
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
