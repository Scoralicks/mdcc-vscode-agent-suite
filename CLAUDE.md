@AGENTS.md

# Claude Code

Os agentes de `.github/agents` estão disponíveis no Claude Code assim:

- `/mdcc-master` (skill em `.claude/skills/mdcc-master`) roda o orquestrador na sessão principal e delega aos subagentes. Use como ponto de entrada padrão para tarefas MDCC.
- `/mdcc-card` (skill em `.claude/skills/mdcc-card`) transforma um card do Jira ou Azure DevOps, uma sprint ou uma JQL/WIQL em plano de implementação, conforme `.github/instructions/work-items.instructions.md`.
- Subagentes em `.claude/agents/mdcc-*.md`: architect, researcher, troubleshooter, validator, dataverse-diagnostician, browser-diagnostician e delivery-planner. Cada um é um wrapper fino que manda ler o `.agent.md` correspondente, que continua sendo a fonte única. Altere o comportamento lá, não no wrapper.
- `mdcc-dataverse-remediator` só funciona com o servidor local `dataverse-mdcc-remediation`, que não vem instalado, e nunca deve ser acionado a partir do fluxo de diagnóstico.
- Subagentes não acionam outros subagentes. Por isso a delegação a Researcher e Validator descrita nos `.agent.md` é feita pela sessão principal.

MCP (`.mcp.json`): `dataverse-mdcc` usa o proxy oficial `@microsoft/dataverse` (perfil `diagnosis`) por `tools/dataverse-mcp/launch.mjs`, que funciona em Windows, Linux e macOS, e `playwright-mdcc` usa o Playwright isolado. As URLs ficam fora do repositório: `MDCC_DATAVERSE_URL` (URL base, sem `/api/mcp`) ou, se ausente, o ambiente ativo de `config/dataverse-mcp.local.json`; e `MDCC_PLAYWRIGHT_ORIGIN`. As escritas são bloqueadas em `.claude/settings.json`. `npm run doctor` mostra o que falta configurar.

Azure DevOps: `ado-mdcc` (`tools/ado-mcp/server.mjs`) segue as mesmas regras do Jira (leitura livre, escrita mínima por comando explícito, `ask` a cada escrita). Configure com `scripts/set-ado-connection.ps1` (PAT por DPAPI ou `-UseAzureCli` para Entra ID) e siga `.github/instructions/ado-mcp.instructions.md`. Detalhes em `docs/ado-mcp.md`.

Jira: `jira-mdcc` (`tools/jira-mcp/server.mjs`) lê histórias para estimativas e atualiza cards (campos, comentário, status; sem criar ou excluir) somente por comando explícito do usuário, com aprovação a cada escrita (`ask` em `.claude/settings.json`). Configure com `scripts/set-jira-connection.ps1` (token protegido por DPAPI, fora do repositório) e siga `.github/instructions/jira-mcp.instructions.md`. Detalhes em `docs/jira-mcp.md`.
