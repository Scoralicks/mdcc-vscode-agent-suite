# Changelog

## 1.2.0 - 2026-10-28 — Qualquer usuário, qualquer ambiente, do card ao plano

- Adiciona o servidor MCP `ado-mdcc` (Azure DevOps Services e Server): WIQL, work items, iterações e estados; escrita mínima (campos, comentário, estado) com controle de revisão, aprovação manual e auditoria; autenticação por PAT (DPAPI ou variável) ou Entra ID via Azure CLI, sem PAT.
- Adiciona o agente **MDCC Delivery Planner**, a skill `/mdcc-card` e o fluxo `work-items.instructions.md`: card do Jira ou Azure DevOps → módulos → abordagem documentada (docs, Learn, GitHub oficial) → estado do ambiente via Dataverse (somente leitura) → plano, testes, riscos e estimativa. O agente não tem ferramentas de escrita nos cards.
- Sincroniza também a documentação oficial de Customer Service e Channel Integration Framework (sparse checkout de `MicrosoftDocs/dynamics-365-customer-engagement`), indexada com o campo `repository`; Researcher e política comum passam a usá-la.
- Torna o `dataverse-mdcc` do Claude Code multiplataforma: `tools/dataverse-mcp/launch.mjs` resolve o ambiente por `MDCC_DATAVERSE_URL` ou pelo catálogo local, valida pela política e localiza o proxy oficial sem depender de `%APPDATA%`.
- Adiciona `npm run doctor`, diagnóstico offline da estação (Node, Git, pwsh, docs, Dataverse, proxy, VS Code MCP, Playwright, Jira, Azure DevOps) com o comando de correção de cada lacuna e sem exibir segredos.
- Corrige a regressão em que `jira-mdcc` no template quebrava presets, preflight e guardrails: servidores de work tracking agora são aceitos somente pela definição exata da allowlist.
- Extrai segredos e protocolo MCP stdio para `tools/shared`, reutilizados por Jira e Azure DevOps.
- Adiciona `npm test`, `npm run test:guardrails` e CI no GitHub Actions com build verificado do pacote.
## 2026-09-25 — Validação autenticada e consolidação Dataverse

- Acrescenta preflight e probe MCP GA de metadados, com resultados sanitizados e execução explícita em development/test no Windows.
- Consolida OAuth interativo, limites do Client Secret e evidências exigidas dos agentes antes de consultar registros.
- Aplica a política de destino ao configurador e aos presets, com regressão para restrição da allowlist.
- Bloqueia caches e arquivos de credenciais, inclusive ocultos, na geração e validação do ZIP.
- Corrige a task de sincronização para PowerShell 7 e documenta a transição separada para remediação.

## 2026-09-21 — Ambientes Dynamics pré-definidos

- Incorpora análise curada da pasta VS_Code e catálogo local de conexões, sem copiar credenciais ou tratar exemplos como fatos do ambiente.
- Adiciona seleção, validação e restauração da conexão MCP por tarefa, preservando o nome `dataverse-mdcc` e o perfil de diagnóstico.
- Separa template distribuível de configuração local; remove definições MCP duplicadas de settings.json.
- Exclui catálogos locais antes do empacotamento e verifica o ZIP temporário antes de substituir o pacote final.
- Adiciona testes de troca de ambiente, rejeição de configurações inválidas e proteção contra arquivos rastreados.

## 1.1.0 - 2026-08-31

- Integra Playwright Test e Playwright MCP com versões fixadas e lockfile.
- Adiciona o agente MDCC Browser Diagnostician, isolado e somente observacional.
- Adiciona smoke test, tarefas de instalação/validação, documentação e guardrails para sessões de clientes.
- Exclui do pacote estados autenticados, relatórios, traces, downloads e binários locais.
- Adiciona configurador visual local para validar e preparar o endpoint Dataverse MCP sem persistir dados do cliente.

## 2026-08-27 — Conexão Dataverse MCP parametrizada por cliente

- removidos endpoints e nomes específicos de cliente do template genérico;
- mantido um único servidor `dataverse-mdcc`, com endpoint solicitado em runtime pelo VS Code;
- adicionada task de preparação que normaliza e valida a URL do cliente sem persistir endpoint ou credenciais;
- reforçados schema, guardrails e validação do pacote contra servidores extras e URLs Dataverse fixas;
- build passa a executar os testes de contexto e segurança antes de empacotar.

## 2026-08-18 — Baseline seguro para testes

- adicionada política universal para os sete agentes: responsabilidade extrema, anti-sycophancy, profundidade verificável, enriquecimento de inputs rasos e foco no objetivo;
- reforçada a pesquisa oficial com três famílias de consulta, matriz afirmação → fonte e validação ao vivo;
- ampliado o índice local para 198 páginas de Contact Center e 19 documentos compartilhados;
- configurado Dataverse MCP por HTTPS `/api/mcp`, com diagnóstico somente leitura e remediação isolada;
- bloqueado handoff automático para escrita e exigidas identidades/contextos separados;
- adicionados schema, guardrails, testes de contexto, testes de endpoint e cenários UAT;
- criado pacote verificável com manifesto SHA-256 e comparação contra o workspace.

