# Validação do ambiente Dataverse pelos agentes MDCC

## Overview

O Master coordena pesquisa oficial e encaminha a investigação ao Dataverse Diagnostician. O Diagnostician usa somente `search`, `describe`, `read_query` e `search_data`. O Validator revisa evidências e limitações. Remediação exige outra sessão, identidade dedicada e aprovação para cada chamada.

O catálogo `config/dataverse-mcp.local.json` escolhe o ambiente; `npm run mcp:select` gera a conexão local do VS Code. A política em `config/dataverse-mcp-policy.json` controla destinos e ferramentas. Os arquivos locais não entram no ZIP. O pacote inclui documentação, agentes, verificadores e testes, sem credenciais.

## Autenticação

| Cliente/modalidade | Uso nesta solução | Evidência e limite |
|---|---|---|
| Copilot no VS Code | HTTP `/api/mcp`, OAuth interativo no armazenamento seguro do VS Code | Cliente principal. Confirmar ambiente, tenant e identidade no login. |
| Proxy oficial `@microsoft/dataverse` no Windows | OAuth interativo, cache protegido, diagnóstico | CLI preview; probe automatizado somente development/test. Sessão distinta do OAuth do VS Code. |
| Client Secret / aplicação | Documentado pelo CLI, não habilitado pelo perfil atual | Exige application user, roles mínimas, provisionamento seguro e revisão do armazenamento; não inserir segredo em argumentos, chat, JSON, TOML ou `.env`. |

Client Secret também é OAuth (client credentials). A documentação do CLI prevê service principal e reutilização de perfis pelo comando `mcp`; isso não comprova conectividade deste ambiente. A escolha operacional desta revisão foi OAuth interativo. Nenhum Client Secret foi solicitado ou testado.

## Execução

1. Confirme o ambiente ativo e sua classificação no catálogo local. Aplique `npm run mcp:select`.
2. Execute `npm run mcp:preflight`. Este comando não autentica nem acessa dados; verifica catálogo, runtime, política e instalação do proxy oficial.
3. No VS Code, inicie `dataverse-mdcc` e conclua OAuth. Para o probe independente no Windows, use o perfil interativo do Dataverse CLI; se necessário, execute localmente `dataverse auth create --environment <URL-base-validada>` e faça login na janela Microsoft. Se o login nativo falhar, execute `dataverse auth create --deviceCode --environment <URL-base-validada>` no terminal local e conclua o fluxo Microsoft antes do probe. Não use opções de senha ou segredo. O CLI é instalado separadamente; o probe não instala ou atualiza pacotes automaticamente.
4. Execute `npm run mcp:probe -- --timeout-seconds 90`. Ele inicializa o proxy, lista ferramentas e chama somente uma operação de metadados de `queue`, com argumentos derivados do schema publicado. Schemas desconhecidos interrompem o teste. Não lê registros de negócio nem altera o ambiente.
5. Selecione **MDCC Dataverse Diagnostician**, confirme tenant, identidade e roles efetivas (incluindo equipes) e solicite a validação do componente. Essas confirmações não são feitas pelo probe.

O probe emite JSON sanitizado em stdout e não salva relatório, token ou payload. O prazo pode variar de 1 a 180 segundos. Resultados de outros ambientes ou sessões não autorizam consultas no ambiente atual.

## Critérios de evidência

| Etapa | O que comprova | O que permanece pendente |
|---|---|---|
| `configuration: verified` | Catálogo/runtime coerentes, endpoint permitido | Login e conectividade |
| `localHandshake: confirmed` | Processo MCP local inicializado | Acesso remoto autenticado |
| `toolDiscovery.status: listed-by-proxy` | Ferramentas anunciadas pelo proxy | Execução efetiva no ambiente |
| `metadataRead.status: confirmed` | Resposta útil de metadados via MCP | Identidade, roles e registros |
| `authentication: confirmed-by-metadata-response` | Acesso autenticado inferido da leitura MCP | Não identifica tenant/usuário nem comprova privilégio mínimo |
| `identity/effectiveRoles: not-verified` | Lacuna explícita | Confirmar sessão e acesso efetivo antes de consultar registros |

Uma falha mantém `ok: false` e um motivo sem texto remoto. `proxy-process-closed` indica encerramento do cliente, não prova falta de consentimento. `timeout-or-cancelled` não prova senha incorreta. `metadata-tool-error` indica falha da chamada; `metadata-not-confirmed` indica resposta insuficiente. Não declare ambiente saudável apenas porque o probe passou.

## Validação MDCC

Após confirmar a identidade e o acesso, descubra nomes lógicos e relações com metadados. Conforme o objetivo, verifique soluções e versões, filas, workstreams, regras de roteamento, capacidade e presença. Defina filtros, limite e colunas antes da leitura. Registre horário UTC, ferramenta, escopo observado, resumo da evidência, conclusão e lacuna. Não presuma nomes de tabelas ou colunas; não extraia conversas, gravações ou dados pessoais para um overview.

O MCP precisa estar habilitado e o aplicativo cliente permitido. O app do proxy e o do VS Code são distintos. Consentimento administrativo e `mcp allow` alteram configuração; o probe não os executa. Não use `dataverse mcp --validate`, pois o comando oficial verifica também o endpoint preview bloqueado pela política.

## Fontes oficiais

- [Autenticação, service principal e caráter preview do Dataverse CLI](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/cli/)
- [Referência dos comandos AUTH e MCP](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/cli/reference)
- [Proxy e clientes não Microsoft](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-other-clients)
- [Dataverse MCP no VS Code](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-vscode)
- [Permissões e ferramentas MCP](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-faq)

## Resultado da revisão — 2026-09-25

- Documentação oficial sincronizada: commit `e5e89943613e3bf5583256bba13f227ebf3829c1`, 234 arquivos Markdown (215 Contact Center e 19 compartilhados).
- 32 testes automatizados aprovados; validadores de contexto dos agentes, Dataverse e Playwright aprovados.
- Preflight do ambiente ativo de desenvolvimento aprovado, proxy oficial instalado `1.0.18`.
- Tentativa MCP real: inicialização local confirmada; processo do proxy encerrou antes da listagem de ferramentas (`proxy-process-closed`). Autenticação, metadados, identidade e roles não confirmados. Nenhum registro lido ou alterado pelo probe.
- Login interativo nativo encerrou com código Windows `0xC0000005`. O fluxo alternativo por código de dispositivo iniciou e foi encerrado após 150 segundos sem concluir a autenticação; é necessário iniciar novo login. Não atribuir a falha a permissões, consentimento ou segredo sem evidência adicional.
- Client Secret não foi testado: a modalidade escolhida pelo usuário foi OAuth interativo.

Confiança na revisão estrutural: 95%. Acesso real ao ambiente permanece não confirmado; para comprová-lo, concluir OAuth, repetir o probe e confirmar tenant/identidade/roles antes das consultas de registros.


