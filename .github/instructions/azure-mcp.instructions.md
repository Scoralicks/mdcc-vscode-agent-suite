# Azure MCP — política de diagnóstico somente leitura

## Escopo

Estas regras se aplicam a qualquer agente que use o servidor azure-mdcc-diagnostics. Leia também config/azure-mcp-policy.json e a política comum MDCC.

## Fronteira de autorização

- O perfil é exclusivamente de diagnóstico. O servidor deve iniciar com --read-only e namespaces explicitamente permitidos.
- A fronteira efetiva é a identidade Microsoft Entra e o Azure RBAC. O arquivo do workspace e o frontmatter do agente são defesas adicionais, não substituem least privilege.
- Use uma identidade diagnóstica dedicada, sem Owner, Contributor, User Access Administrator ou permissões de escrita equivalentes.
- Limite o escopo ao resource group, recursos e workspaces necessários. Não presuma que Reader concede leitura de dados do Log Analytics.
- Não execute Azure CLI, PowerShell, REST, ARM/Bicep/Terraform, deployment, publish, send, create, update ou delete para contornar o modo somente leitura.
- Nunca desabilite confirmação de usuário, use Bypass/Autopilot, conceda Always Allow ao servidor inteiro ou amplie namespaces durante um diagnóstico.

## Tratamento de dados

- Logs podem conter PII, números telefônicos, endereços, tokens, URLs assinadas, headers e payloads. Solicite apenas colunas e intervalos necessários, minimize resultados e redija segredos na resposta.
- Nunca consulte ou revele Key Vault secrets, connection strings, access keys, tokens, certificados privados ou conteúdo de mensagens/chamadas sem necessidade e autorização compatível.
- Use UTC, intervalo temporal limitado e identificadores de correlação. Não faça varredura ampla de subscriptions ou workspaces quando o escopo puder ser reduzido.
- Não persista dados de ambiente, resultados de logs ou identificadores sensíveis no repositório.

## Sequência de diagnóstico

1. Comece por documentação oficial via microsoft-learn; não consulte o ambiente para perguntas conceituais.
2. Antes de uma consulta Azure, registre tenant quando relevante, subscription, resource group, resource ID, região, janela UTC e identificadores disponíveis.
3. Confirme resource provider, plano de controle ou dados e serviço proprietário de cada evidência.
4. Inspecione, conforme aplicável: inventário, Resource Health, Activity Log, métricas, Diagnostic Settings, destino, workspace/tabelas, Event Grid topics/subscriptions/delivery/dead-letter e logs da aplicação receptora.
5. Separe ausência do evento, falha de roteamento, falha de entrega e falha do consumidor. Ausência de log não prova ausência do evento.
6. Entregue diagnóstico e plano de correção. Qualquer mudança Azure deve ocorrer em sessão operacional separada, com identidade e aprovação próprias.

## Bloqueios

Interrompa a consulta e entregue somente orientação quando:

- a identidade ativa ou o escopo Azure não estiver confirmado;
- a operação disponível não estiver anotada como read-only;
- a consulta puder expor segredo ou dados pessoais desnecessários;
- o usuário pedir alteração, publicação, envio, criação, update ou delete;
- a evidência exigir acesso superior ao mínimo necessário.
