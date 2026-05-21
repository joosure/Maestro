# Maestro Roadmap

Idiomas: [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [Español](./ROADMAP.es.md) · [More](./LANGUAGES.md)

## Objetivo

Maestro tiene un objetivo simple:

> **Hacer que los AI agents sean más fáciles, seguros y confiables para equipos de ingeniería reales.**

Muchos coding agents ya pueden escribir código. Los equipos necesitan más que generación de código:

- el trabajo debe venir de sistemas reales como TAPD, Linear y futuras plataformas;
- el código debe venir de un repositorio Git y una rama configurados explícitamente;
- cada ejecución debe tener un espacio de trabajo aislado para que las tareas no interfieran entre sí;
- las personas deben entender qué hizo el agent, qué cambió y por qué falló;
- los pasos de mayor riesgo deben seguir siendo revisables;
- los equipos deben poder ampliar el uso gradualmente, no abrir todos los permisos el primer día.

Este roadmap está organizado por valor para el usuario, no por nombres de módulos internos.

---

## Corto plazo: hacer Maestro más fácil de probar

Un usuario nuevo debería poder entender y ejecutar Maestro sin aprender primero toda la arquitectura.

Trabajo previsto:

- una demo local más simple;
- instrucciones de Quick Start más claras;
- capturas, GIFs o videos cortos;
- tareas de ejemplo que muestren el flujo completo;
- una explicación clara de por qué importan los espacios aislados: paralelismo, aislamiento, limpieza y revisión;
- una explicación de los nombres de compatibilidad `symphony` que todavía quedan;
- un camino claro desde la demo local hasta una configuración real.

Escenarios que queremos mostrar mejor:

- tarea TAPD a GitHub Pull Request;
- tarea Linear a GitHub Pull Request;
- análisis de requisitos antes de programar;
- triage de trabajo entrante;
- sugerencias de reviewer;
- comparación de Codex, Claude Code y OpenCode en tareas similares.

Éxito significa que un lector nuevo puede responder en minutos:

> “¿Qué hace Maestro y por qué podría necesitarlo mi equipo?”

---

## Siguiente: conectar agents a workflows reales de proyecto

Maestro debe ayudar a que los agents trabajen desde los sistemas que los equipos ya usan, no obligarlos a crear una nueva cola de tareas.

Trabajo previsto:

- mejorar los flujos actuales de TAPD y Linear;
- hacer más comprensibles estados, comentarios, enlaces y resultados;
- hacer que las plantillas de workflow sean más fáciles de encontrar, copiar y adaptar;
- soportar más tareas comunes: bugs, pequeñas features, análisis de requisitos, refinamiento, triage y sugerencias de revisión;
- distinguir claramente el soporte actual de integración de los objetivos futuros;
- prepararse para integraciones como Jira, GitHub Issues, GitLab, Gitea, Bitbucket y Feishu Project.

Éxito significa que los equipos pueden empezar desde su flujo de proyecto actual, sin cambiar cómo gestionan el trabajo solo para usar agents.

---

## Medio plazo: hacer el trabajo del agent más confiable

Un equipo no debería confiar en una ejecución solo porque el agent dice “listo”.

Trabajo previsto:

- historial de ejecuciones más claro;
- resúmenes más fáciles de leer;
- mejores enlaces entre tareas, cambios Git, logs y material de revisión;
- razones de fallo más claras;
- mejor redacción de logs;
- un dashboard más útil;
- checkpoints visibles antes de escribir en sistemas reales, empujar ramas o crear PRs;
- separación clara entre demo local, evaluación confiable, piloto de equipo y operación productiva.

Éxito significa que un reviewer puede responder:

- ¿Qué hizo el agent?
- ¿Desde qué tarea y repositorio Git trabajó?
- ¿Qué cambió?
- ¿Por qué se detuvo?
- ¿Qué requiere confirmación humana?
- ¿Es seguro continuar?

---

## Largo plazo: ayudar a los equipos a usar agents a escala

Una demo con un solo agent es útil. El uso a nivel de equipo requiere operaciones más sólidas.

Trabajo previsto:

- ejecutar varias tareas al mismo tiempo de forma segura;
- mantener workspaces y registros separados para distintos proyectos y tareas;
- elegir distintos agents según el tipo de tarea;
- gestionar cuentas, credenciales, cuota y coste con más claridad;
- mejorar entornos de ejecución para equipos;
- mejorar reintentos y recuperación;
- soportar puntos claros de aprobación humana;
- ayudar a comparar la efectividad real de distintos agents y workflows.

Éxito significa que los equipos pueden ampliar el uso de agents gradualmente manteniendo seguridad, coste y calidad bajo control.

---

## Documentación y comunidad

Maestro debe ser comprensible antes de parecer poderoso.

Trabajo previsto:

- mantener el README principal corto y basado en ejemplos;
- mover detalles técnicos profundos a documentos separados;
- mantener activamente English y Simplified Chinese;
- conservar otras traducciones y recibir mejoras de la comunidad;
- añadir guías de contribución para sistemas de proyecto, agents, plataformas de código y workflow templates;
- publicar más ejemplos de escenarios reales de ingeniería.

Éxito significa que los contributors pueden encontrar un punto de entrada útil sin leer todo el código primero.

---

## No objetivos por ahora

Maestro no intenta ayudar a los equipos a saltarse revisión, pruebas o criterio de release.

Nos importa más:

- conectar agents con tareas reales;
- hacer visible el origen del código y de la tarea;
- mantener el proceso rastreable;
- conservar control humano en pasos de alto riesgo;
- preservar registros útiles;
- ampliar la automatización solo a medida que crece la confianza.

La automatización debe crecer con evidencia, no con deseo.

---

## Enfoque actual

El enfoque actual es hacer Maestro más fácil de entender, probar y evaluar de forma segura:

1. simplificar el README público;
2. añadir un roadmap en lenguaje claro;
3. mejorar la guía de la demo local;
4. describir el soporte actual sin llamar “integrados” a sistemas externos;
5. explicar por qué importan los espacios aislados;
6. añadir ejemplos con TAPD, Linear, GitHub, CNB y combinaciones reales de agents;
7. mantener detalles técnicos disponibles sin obligar a cada lector nuevo a empezar por ellos.

---

## Cómo contribuir

Contribuciones útiles:

- mejores ejemplos;
- documentación más clara;
- plantillas de workflow más seguras;
- nuevas integraciones de sistemas de proyecto;
- nuevas integraciones de coding agents;
- nuevas integraciones de plataformas de código;
- mejoras del dashboard;
- cobertura de pruebas con workflows reales;
- revisión de traducciones por hablantes nativos.

Empieza con el flujo local memory/mock y avanza gradualmente hacia sistemas reales.
