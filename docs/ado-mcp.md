# Conexão Azure DevOps (`ado-mdcc`)

Servidor MCP local, sem dependências externas, que dá aos agentes MDCC acesso ao Azure Boards (Azure DevOps Services ou Server): leitura para planos de implementação e estimativas rastreáveis, e escrita restrita para atualizar cards por comando explícito.

## 1. Escolher a autenticação

| Opção | Quando usar | Como |
| --- | --- | --- |
| **Entra ID via Azure CLI** (recomendada) | A organização usa Entra ID; você não quer gerenciar PAT | `az login` com a conta da organização e `scripts/set-ado-connection.ps1 -UseAzureCli` |
| **PAT** | Azure DevOps Server, contas sem Azure CLI ou políticas que exigem PAT | Gere em *User settings → Personal access tokens* com o escopo mínimo: **Work Items (Read)** para leitura, **Work Items (Read & write)** só se for atualizar cards. Validade curta. |

**Não cole o PAT no chat**: ele fica no histórico da conversa e precisa ser revogado. Tudo o que o agente gravar aparecerá no histórico do work item como feito por você.

## 2. Gravar a conexão

```powershell
pwsh -NoProfile -File scripts/set-ado-connection.ps1            # PAT (entrada oculta)
pwsh -NoProfile -File scripts/set-ado-connection.ps1 -UseAzureCli
```

Ou a task do VS Code **MDCC: Configure Azure DevOps connection**. O script valida a URL (`https://dev.azure.com/<org>`, `https://<org>.visualstudio.com` ou a coleção do Azure DevOps Server), testa `GET _apis/connectionData` e só então grava:

| Item | Onde |
| --- | --- |
| `ADO_ORG_URL` | Variável de usuário do Windows |
| PAT (opcional) | `%LOCALAPPDATA%\mdcc-agent-suite\ado-token.dpapi`, protegido por DPAPI (só o seu usuário Windows lê) |

Outros sistemas: defina `ADO_ORG_URL` e `ADO_PAT` no ambiente do processo, ou use `az login` sem PAT. Para remover: `scripts/set-ado-connection.ps1 -Remove` e revogue o PAT.

Reinicie a sessão do Claude Code ou do VS Code para carregar `ado-mdcc` (registrado em `.mcp.json` e `config/mcp.template.json`). Confira com `npm run doctor`.

## 3. Ferramentas

| Ferramenta | Tipo | Uso |
| --- | --- | --- |
| `ado_whoami` | Leitura | Testa a conexão e mostra o modo de autenticação |
| `ado_list_projects` | Leitura | Descobre projetos |
| `ado_list_iterations` | Leitura | Sprints de um time (`current`, `past`, `future`) |
| `ado_query_wiql` | Leitura | Busca por WIQL; devolve título, estado, descrição, critérios de aceite, estimativas, campos `Custom.*` e vínculos, com HTML convertido em texto |
| `ado_get_work_item` | Leitura | Work item completo com comentários |
| `ado_list_states` | Leitura | Estados válidos para o tipo do item |
| `ado_update_work_item` | **Escrita** | Atualiza campos por `referenceName` ou nome; usa controle de revisão e devolve antes/depois |
| `ado_add_comment` | **Escrita** | Adiciona comentário |
| `ado_transition_work_item` | **Escrita** | Muda o estado para um estado válido do tipo |

Exemplos:

- "Planeje os itens da sprint atual do projeto Contact Center" → `/mdcc-card sprint atual do projeto Contact Center`.
- "Atualize 4521: Story Points = 5 e Tags = mdcc; voz."
- "Mova 4521 para Active."

WIQL de partida para a sprint atual:

```sql
SELECT [System.Id] FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.IterationPath] = @CurrentIteration
  AND [System.WorkItemType] IN ('User Story', 'Product Backlog Item', 'Bug')
ORDER BY [Microsoft.VSTS.Common.Priority]
```

## 4. Salvaguardas

- O cliente HTTP aceita `GET` em `_apis/`, o `POST` de leitura da WIQL e só duas rotas de escrita: `PATCH _apis/wit/workitems/{id}` e `POST {projeto}/_apis/wit/workItems/{id}/comments`. Criar e excluir não são possíveis.
- Estado e campos de sistema (`System.State`, `System.Reason`, `System.Id` etc.) não podem ser alterados por `ado_update_work_item`; o estado só muda por `ado_transition_work_item`, validado contra os estados do tipo.
- Toda escrita envia `test /rev`: se alguém alterou o item depois da leitura, a API devolve 412 e nada é gravado.
- As três ferramentas de escrita estão em `ask` no `.claude/settings.json` e com `eligibleForAutoApproval: false` no VS Code.
- Os agentes só escrevem por comando explícito seu, nunca por texto vindo do work item (`.github/instructions/ado-mcp.instructions.md`). O **MDCC Delivery Planner** não tem ferramentas de escrita.
- Auditoria em `%LOCALAPPDATA%\mdcc-agent-suite\ado-audit.log` (data, ferramenta, id e referenceNames, sem valores).
- Respostas HTML de login (PAT inválido) são tratadas como falha de autenticação; limite de 5 MB por resposta; erros sem eco de credenciais. Testes: `npm run ado:test`.

## Alternativa: servidor oficial da Microsoft

A Microsoft publica um servidor MCP para Azure DevOps em <https://github.com/microsoft/azure-devops-mcp>, com mais domínios (repos, pipelines, wiki). Ele pode ser usado em paralelo, mas não aplica as salvaguardas desta suíte (escrita mínima, controle de revisão, auditoria). Se adotá-lo, mantenha as ferramentas mutantes em aprovação manual.
