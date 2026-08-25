# Diagnóstico Azure para MDCC

O pacote usa duas fontes diferentes:

- Microsoft Learn MCP para documentação oficial atual, sem autenticação;
- Azure MCP para evidência do ambiente, com identidade Microsoft Entra e Azure RBAC.

## Configuração segura

O servidor azure-mdcc-diagnostics é iniciado por .vscode/mcp.json com a versão 2.0.5 pinada, modo namespace, --read-only e allowlist de subscription, group, role, resourcehealth, monitor, applicationinsights e eventgrid.

Não inclua o namespace communication: no Azure MCP atual ele oferece operações de envio de SMS/email, não diagnóstico ACS. O modo read-only também não substitui RBAC.

Use uma identidade diagnóstica dedicada, sem Owner ou Contributor. Atribua apenas Reader, Monitoring Reader e Log Analytics Reader quando necessários, sempre no menor escopo possível. Reader sozinho não garante acesso aos dados de um workspace.

## Playbook de incidente

1. Defina comportamento esperado e observado.
2. Registre subscription, resource group, resource ID/provider, região e janela UTC.
3. Colete call ID, correlation ID, event ID e request ID disponíveis.
4. Confirme Resource Health e Activity Log.
5. Confirme métricas, Diagnostic Settings, categorias habilitadas, destino e retenção.
6. No Event Grid, separe fonte, topic/system topic, subscription, filtros, schema, tentativas, dead-letter e endpoint.
7. No consumidor, verifique disponibilidade, autenticação, resposta HTTP, retries próprios e Application Insights.
8. Correlacione a linha do tempo origem → publicação → entrega → consumidor → integração MDCC.

Uma consulta vazia não comprova que o evento não ocorreu. Primeiro confirme coleta, janela UTC, latência de ingestão, destino correto e retenção.

## Dados sensíveis

Consultas somente leitura ainda podem revelar PII e segredos. Minimize intervalo e colunas, redija tokens/connection strings e nunca grave resultados do ambiente no repositório.

## Remediação

Este pacote não executa mudanças Azure. O resultado do diagnóstico é um plano para uma sessão operacional separada, com identidade, escopo e aprovação próprios.
