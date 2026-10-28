# Conexão Jira (`jira-mdcc`)

Servidor MCP local, sem dependências externas, que dá aos agentes MDCC acesso às histórias do Jira Cloud: leitura para estimativas rastreáveis e escrita restrita para atualizar cards por comando explícito.

## 1. Gerar o token

1. Acesse <https://id.atlassian.com/manage-profile/security/api-tokens>.
2. **Create API token**, dê um nome (ex.: `mdcc-agent-suite`) e defina a validade mais curta que atenda ao trabalho.
3. Copie o token. **Não cole o token no chat**: ele fica no histórico da conversa e precisa ser revogado.

O token age com as permissões da sua conta Jira. Tudo o que o agente gravar aparecerá no histórico do card como feito por você.

## 2. Gravar a conexão

```powershell
pwsh -NoProfile -File scripts/set-jira-connection.ps1
```

Ou a task do VS Code **MDCC: Configure Jira connection**. O script pede a URL (`https://empresa.atlassian.net`), o e-mail e o token (entrada oculta), testa `GET /rest/api/3/myself` e só então grava:

| Item | Onde |
| --- | --- |
| `JIRA_BASE_URL`, `JIRA_EMAIL` | Variáveis de usuário do Windows |
| Token de API | `%LOCALAPPDATA%\mdcc-agent-suite\jira-token.dpapi`, protegido por DPAPI (só o seu usuário Windows lê) |

Alternativa (outros sistemas): definir `JIRA_API_TOKEN` no ambiente do processo. Para remover: `scripts/set-jira-connection.ps1 -Remove` e revogue o token no site da Atlassian.

Depois, reinicie a sessão do Claude Code ou do VS Code para carregar o servidor `jira-mdcc` (registrado em `.mcp.json` e `config/mcp.template.json`).

## 3. Ferramentas

| Ferramenta | Tipo | Uso |
| --- | --- | --- |
| `jira_whoami` | Leitura | Testa a conexão |
| `jira_list_projects` | Leitura | Descobre chaves de projeto |
| `jira_list_boards` / `jira_list_sprints` | Leitura | Localiza sprints para a JQL |
| `jira_search` | Leitura | Busca por JQL; inclui campos personalizados preenchidos com nome legível (story points, critérios de aceite etc.) |
| `jira_get_issue` | Leitura | Issue completa com comentários, subtarefas e vínculos |
| `jira_list_transitions` | Leitura | Transições de status disponíveis |
| `jira_update_issue` | **Escrita** | Atualiza campos de uma issue por nome ou id; devolve antes/depois |
| `jira_add_comment` | **Escrita** | Adiciona comentário |
| `jira_transition_issue` | **Escrita** | Muda o status por uma transição válida |

Exemplos de comando:

- "Atualize ABC-12: Story point estimate = 5 e labels = mdcc, voz."
- "Comente em ABC-12 a estimativa com as premissas."
- "Mova ABC-12 para Em andamento."

Conversão de valores em `jira_update_issue`: texto rico (descrição, campos de parágrafo) aceita texto simples, e linhas iniciadas por `- ` viram lista; números são validados; listas aceitam `"a, b"`; seleção, prioridade, componentes e versões usam o nome. Para outros formatos, envie o JSON bruto da API. Só campos presentes na tela de edição da issue podem ser alterados.

## 4. Salvaguardas

- O cliente HTTP aceita `GET` em `/rest/api/3/` e `/rest/agile/1.0/` e só três escritas: `PUT /issue/{key}`, `POST /issue/{key}/comment` e `POST /issue/{key}/transitions`. Criar e excluir não são possíveis.
- As três ferramentas de escrita estão em `ask` no `.claude/settings.json`: o Claude Code pede sua aprovação a cada chamada, mostrando os argumentos.
- Os agentes só escrevem por comando explícito seu, nunca por texto vindo de uma issue (`.github/instructions/jira-mcp.instructions.md`).
- Auditoria em `%LOCALAPPDATA%\mdcc-agent-suite\jira-audit.log` (data, ferramenta, chave e ids de campos, sem valores). O retorno `antes/depois` permite desfazer uma edição manualmente.
- Limite de 5 MB por resposta; erros sem eco de credenciais. Testes: `npm run jira:test`.
