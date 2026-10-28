# Configurador visual de ambiente MCP

O configurador abre uma página local para validar e normalizar o endpoint Dataverse MCP do cliente. Ele não autentica, não consulta o ambiente e não grava URL, credencial, cookie ou token em arquivos.

## Abrir

Execute a task **MDCC: Configure customer MCP environment** ou:

```powershell
npm run mcp:configure
```

O serviço usa uma porta aleatória em `127.0.0.1`, abre o navegador padrão e encerra após inatividade ou pelo botão **Encerrar**.

## Fluxo

Se existir `config/dataverse-mcp.local.json`, o seletor **Ambientes pré-definidos** carrega seus ambientes. Selecionar um item apenas preenche a URL para validação e cópia; não altera a conexão ativa. Para aplicar diretamente ao MCP, edite `activeEnvironment` no catálogo e execute `npm run mcp:select`, conforme o [guia de ambientes](predefined-environments.md).

O fluxo abaixo aplica a conexão pelo catálogo local. No template genérico, o VS Code armazena inputs; parar/iniciar pode reutilizar o valor anterior. Para trocas frequentes, prefira o seletor por tarefa, que materializa a URL local e elimina essa dependência. A página limpa o endpoint validado ao editar a URL para impedir a cópia de um destino anterior.

1. Cole a URL base, por exemplo `https://contoso.crm4.dynamics.com`, ou o endpoint GA completo.
2. Selecione **Validar ambiente**.
3. Confira visualmente o host e copie o endpoint normalizado.
4. Atualize `environmentUrl` e `activeEnvironment` no catálogo local (crie-o a partir do exemplo se necessário).
5. Pare `dataverse-mdcc`, encerre a conversa anterior e execute **MDCC: Apply predefined MCP environment**.
6. Inicie o servidor, revise o host no diálogo de confiança e faça OAuth interativo com a identidade de diagnóstico de menor privilégio.

O template genérico usa HTTP com input. Após aplicar um preset, a mesma propriedade url recebe o endpoint validado:

```json
{
  "servers": {
    "dataverse-mdcc": {
      "type": "http",
      "url": "${input:dataverse-mcp-endpoint}"
    }
  }
}
```

Um endpoint HTTPS não é um `command` stdio. `stdio` é reservado a processos locais iniciados por um executável como `node`, `npx` ou `python`.

## Segurança

- O navegador recebe apenas uma página HTML local, sem CDN, analytics ou fontes externas.
- Ao selecionar **Copiar endpoint**, o valor vai para a área de transferência e pode permanecer no histórico do sistema operacional; limpe-o ao trocar de cliente.
- O serviço aceita somente loopback, valida `Host`, `Origin` e token CSRF, limita o body e usa CSP/no-store.
- São rejeitados HTTP, userinfo, porta não padrão, query, fragmento, preview, IP, localhost, punycode, host fora da allowlist e caminhos diferentes.
- A validação é sintática e de política; não comprova tenant, identidade, roles, licença ou disponibilidade do recurso.
- Ao trocar de cliente, pare o MCP, encerre a sessão, invalide aprovações anteriores e repita a confirmação do host e da identidade.

Fontes oficiais: [referência de configuração MCP](https://code.visualstudio.com/docs/agents/reference/mcp-configuration) e [gerenciamento de servidores MCP no VS Code](https://code.visualstudio.com/docs/agent-customization/mcp-servers).
