# Changelog

## 2026-08-24 — Azure intelligence and read-only diagnostics

- criado MDCC Azure Specialist com ownership explícito de ACS, Event Grid e observabilidade;
- integrado Microsoft Learn MCP para documentação oficial atual;
- integrado Azure MCP 2.0.5 pinado, --read-only e allowlist de namespaces;
- adicionadas política Azure MCP, least privilege, minimização de logs e proibição de remediação;
- criado corpus Azure direcionado e indexado a partir do MicrosoftDocs/azure-docs;
- ampliados catálogo, Researcher, Architect, Troubleshooter, Master e Validator;
- adicionados playbook, guardrails automatizados e cenários de regressão Azure.
- adicionado GitHub Actions para sincronizar fontes, executar guardrails, validar o Azure MCP pinado, gerar o ZIP e publicar o artefato.

## 2026-08-18 — Baseline seguro para testes

- adicionada política universal para os sete agentes: responsabilidade extrema, anti-sycophancy, profundidade verificável, enriquecimento de inputs rasos e foco no objetivo;
- reforçada a pesquisa oficial com três famílias de consulta, matriz afirmação → fonte e validação ao vivo;
- ampliado o índice local para 198 páginas de Contact Center e 19 documentos compartilhados;
- configurado Dataverse MCP por HTTPS `/api/mcp`, com diagnóstico somente leitura e remediação isolada;
- bloqueado handoff automático para escrita e exigidas identidades/contextos separados;
- adicionados schema, guardrails, testes de contexto, testes de endpoint e cenários UAT;
- criado pacote verificável com manifesto SHA-256 e comparação contra o workspace.
