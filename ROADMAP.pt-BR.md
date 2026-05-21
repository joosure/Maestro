# Maestro Roadmap

Idiomas: [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [Português](./ROADMAP.pt-BR.md) · [More](./LANGUAGES.md)

## Objetivo

Maestro tem um objetivo simples:

> **Tornar AI agents mais fáceis, seguros e confiáveis para equipes reais de engenharia.**

Muitos coding agents já conseguem escrever código. Equipes precisam de mais do que geração de código:

- o trabalho deve vir de sistemas reais como TAPD, Linear e futuras plataformas;
- o código deve vir de um repositório Git e uma branch configurados explicitamente;
- cada execução deve ter uma área de trabalho isolada para que tarefas não interfiram entre si;
- pessoas devem entender o que o agent fez, o que mudou e por que falhou;
- etapas de maior risco devem continuar revisáveis;
- equipes devem ampliar o uso gradualmente, em vez de abrir todas as permissões no primeiro dia.

Este roadmap é organizado por valor para o usuário, não por nomes de módulos internos.

---

## Curto prazo: tornar Maestro mais fácil de experimentar

Um usuário novo deve conseguir entender e rodar Maestro sem aprender toda a arquitetura primeiro.

Trabalho planejado:

- uma demo local mais simples;
- instruções de Quick Start mais claras;
- screenshots, GIFs ou vídeos curtos;
- tarefas de exemplo que mostrem o fluxo completo;
- explicação clara do valor das áreas isoladas: paralelismo, isolamento, limpeza e revisão;
- explicação dos nomes de compatibilidade `symphony` que ainda existem;
- caminho claro da demo local para uma configuração real.

Cenários que queremos demonstrar melhor:

- tarefa TAPD para GitHub Pull Request;
- tarefa Linear para GitHub Pull Request;
- análise de requisitos antes de codar;
- triage de trabalho entrante;
- sugestões de reviewer;
- comparação de Codex, Claude Code e OpenCode em tarefas parecidas.

Sucesso significa que um novo leitor consegue responder em poucos minutos:

> “O que Maestro faz e por que minha equipe pode precisar dele?”

---

## Próximo: conectar agents a workflows reais de projeto

Maestro deve ajudar agents a trabalhar a partir dos sistemas que as equipes já usam, sem forçar uma nova fila de tarefas.

Trabalho planejado:

- melhorar os fluxos atuais de TAPD e Linear;
- tornar estados, comentários, links e resultados mais compreensíveis;
- tornar templates de workflow mais fáceis de encontrar, copiar e adaptar;
- suportar tarefas comuns: bugs, pequenas features, análise de requisitos, refinamento, triage e sugestões de revisão;
- distinguir claramente o suporte atual de integração dos alvos futuros;
- preparar integrações como Jira, GitHub Issues, GitLab, Gitea, Bitbucket e Feishu Project.

Sucesso significa que equipes podem começar do fluxo de projeto atual, sem mudar como gerenciam trabalho apenas para usar agents.

---

## Médio prazo: tornar o trabalho do agent mais confiável

Uma equipe não deve confiar em uma execução só porque o agent disse “concluído”.

Trabalho planejado:

- histórico de execução mais claro;
- resumos mais fáceis de ler;
- melhores links entre tarefas, mudanças Git, logs e material de revisão;
- motivos de falha mais claros;
- melhor redaction de logs;
- dashboard mais útil;
- checkpoints visíveis antes de escrever em sistemas reais, fazer push de branches ou criar PRs;
- separação clara entre demo local, avaliação confiável, piloto de equipe e operação de produção.

Sucesso significa que um reviewer consegue responder:

- O que o agent fez?
- De qual tarefa e repositório Git ele trabalhou?
- O que mudou?
- Por que ele parou?
- O que ainda precisa de confirmação humana?
- É seguro continuar?

---

## Longo prazo: ajudar equipes a usar agents em escala

Uma demo com um agent é útil. Uso em nível de equipe exige operação mais forte.

Trabalho planejado:

- executar várias tarefas ao mesmo tempo com segurança;
- manter workspaces e registros separados para diferentes projetos e tarefas;
- escolher agents diferentes para tipos de tarefa diferentes;
- gerenciar contas, credenciais, quota e custo com mais clareza;
- melhorar ambientes de execução para equipes;
- melhorar retry e recuperação;
- oferecer pontos claros de aprovação humana;
- ajudar equipes a comparar a efetividade real de agents e workflows diferentes.

Sucesso significa que equipes podem ampliar o uso de agents gradualmente mantendo segurança, custo e qualidade sob controle.

---

## Documentação e comunidade

Maestro deve ser compreensível antes de parecer poderoso.

Trabalho planejado:

- manter o README principal curto e baseado em exemplos;
- mover detalhes técnicos profundos para documentos separados;
- manter English e Simplified Chinese ativamente;
- manter outras traduções disponíveis e receber melhorias da comunidade;
- adicionar guias de contribuição para sistemas de projeto, agents, plataformas de código e workflow templates;
- publicar mais exemplos de cenários reais de engenharia.

Sucesso significa que contributors encontram um ponto de entrada útil sem ler todo o código primeiro.

---

## Não objetivos por enquanto

Maestro não tenta ajudar equipes a pular revisão, testes ou julgamento de release.

Nós nos importamos mais com:

- conectar agents a tarefas reais;
- tornar visível a origem do código e da tarefa;
- manter o processo rastreável;
- preservar controle humano em passos de alto risco;
- manter registros úteis;
- ampliar automação somente conforme a confiança cresce.

Automação deve crescer com evidência, não com desejo.

---

## Foco atual

O foco atual é tornar Maestro mais fácil de entender, experimentar e avaliar com segurança:

1. simplificar o README público;
2. adicionar um roadmap em linguagem clara;
3. melhorar a orientação da demo local;
4. descrever o suporte atual sem chamar sistemas externos de “embutidos”;
5. explicar por que áreas de trabalho isoladas importam;
6. adicionar exemplos com TAPD, Linear, GitHub, CNB e combinações reais de agents;
7. manter detalhes técnicos disponíveis sem obrigar todo novo leitor a começar por eles.

---

## Como contribuir

Contribuições úteis incluem:

- exemplos melhores;
- documentação mais clara;
- templates de workflow mais seguros;
- novas integrações de sistemas de projeto;
- novas integrações de coding agents;
- novas integrações de plataformas de código;
- melhorias no dashboard;
- cobertura de testes com workflows reais;
- revisão de tradução por falantes nativos.

Comece pelo fluxo local memory/mock e avance gradualmente para sistemas reais.
