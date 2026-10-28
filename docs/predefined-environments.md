# Ambientes Dynamics predefinidos

Depois da habilitação inicial do MCP, OAuth e permissões de diagnóstico em cada ambiente, a troca exige alterar apenas a seleção da conexão e aplicar a configuração. Não é necessário duplicar agentes, políticas ou servidores. A preparação local não comprova autenticação nem conectividade.

## Configuração local e pacote distribuível

| Arquivo | Uso |
|---|---|
| `config/dataverse-mcp.local.json` | Catálogo local com URLs e ambiente ativo; ignorado pelo Git e excluído do pacote. |
| `config/dataverse-mcp.example.json` | Exemplo genérico para criar o catálogo de outra instalação. |
| `config/dataverse-mcp.local.schema.json` | Contrato dos campos do catálogo. |
| `config/mcp.template.json` | Template canônico versionável, sem URL de cliente. |
| `.vscode/mcp.json` | Configuração local gerada e ignorada pelo Git, consumida pelo VS Code. |

O comando mantém o nome `dataverse-mdcc`, valida e normaliza a URL para HTTPS e `/api/mcp` e materializa o endpoint no servidor HTTP. A configuração do Playwright vem do template; selecionar um ambiente Dataverse não configura uma sessão de navegador. O pacote recebe o template genérico no lugar da configuração local.

A URL identifica o ambiente, mas não autentica o usuário. Nunca inclua tokens, senhas, cookies, client secrets ou cabeçalhos de autenticação no catálogo. OAuth permanece sob responsabilidade do cliente.

## Primeiro uso

1. Confirme a habilitação do Dataverse MCP e do cliente GitHub Copilot no ambiente. Prepare uma identidade com acesso de leitura mínimo, incluindo roles efetivas herdadas de equipes. Consulte a [configuração oficial do ambiente](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-disable).
2. Se o catálogo local já existir, preserve-o. Em uma instalação nova, copie `config/dataverse-mcp.example.json` para `config/dataverse-mcp.local.json` e substitua a URL de exemplo pela URL do ambiente autorizado.
3. Confira o catálogo, selecione o `activeEnvironment` e aplique a conexão pelo procedimento abaixo.
4. Inicie `dataverse-mdcc` em **MCP: List Servers**, confirme o host e faça autenticação interativa quando solicitada. Confirme tenant, identidade e roles antes de consultar dados.
5. Use **MDCC Dataverse Diagnostician** e comece por uma consulta de metadados somente leitura. Registre o resultado sem credenciais ou dados pessoais desnecessários.

O transporte HTTP e o caminho `/api/mcp` seguem a [documentação oficial de conexão do Dataverse ao VS Code](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-vscode). A habilitação administrativa não é executada pelo seletor local.

## Selecionar ou trocar ambiente

1. Pare `dataverse-mdcc` e encerre a conversa anterior. As aprovações e evidências anteriores não se aplicam ao novo ambiente.
2. Liste os ambientes disponíveis:

   ```powershell
   npm run mcp:select -- --list
   ```

3. Em `config/dataverse-mcp.local.json`, altere somente `activeEnvironment` para o `id` desejado. Para corrigir o destino de um cadastro existente, edite seu `environmentUrl`.
4. Execute a task **MDCC: Apply predefined MCP environment** ou:

   ```powershell
   npm run mcp:select
   npm run mcp:select -- --check
   ```

5. Confira o host apresentado, reinicie `dataverse-mdcc` e confirme novamente tenant, identidade e acesso efetivo. Trocar a URL não encerra sessões OAuth nem revoga permissões automaticamente.

Edite o catálogo e reaplique; alterações manuais na configuração gerada podem divergir do ambiente ativo e serão rejeitadas pelo `--check`. O comando não inicia servidores, não autentica e não altera dados no Dynamics.

O catálogo aceita de 1 a 100 ambientes, com identificadores únicos e endpoints distintos. Cada entrada contém `id`, `label`, `environmentUrl` e `classification`; as classificações permitidas são `development`, `test`, `production` e `unconfirmed`. A classificação é informação operacional declarada, não detecção automática nem controle de permissão. Um ambiente sem classificação comprovada permanece `unconfirmed`.

## Retornar ao input manual

```powershell
npm run mcp:select -- --reset
```

Esse comando restaura o template em `.vscode/mcp.json`, preservando o catálogo local. O template solicita o endpoint por input. Inputs são armazenados para reutilização; reiniciar o servidor não significa solicitar um novo valor. A documentação também informa que servidores com inputs interativos não são encaminhados ao Agent Host. Por isso o fluxo de ambientes predefinidos materializa a URL localmente. Consulte a [referência de configuração MCP do VS Code](https://code.visualstudio.com/docs/agents/reference/mcp-configuration).

## Git, diagnóstico e limites

Adicionar um caminho ao `.gitignore` não retira um arquivo já rastreado. O seletor recusa aplicar URLs quando detecta rastreamento ou não consegue verificar o estado do Git. Nessa situação, confira a raiz correta e a propriedade do repositório; se o arquivo já estiver rastreado, retire somente a configuração local do índice antes de reaplicar. Não desabilite globalmente a verificação de propriedade como atalho.

O `--check` valida consistência entre catálogo, template e configuração local. Não testa rede, OAuth, tenant, licenciamento ou suporte do recurso. Uma classificação `production` não autoriza escrita. As barreiras de diagnóstico continuam sendo as ferramentas do agente e as permissões efetivas do Dataverse; o catálogo não concede nem reduz privilégios. Remediação segue a sessão dedicada e a aprovação por chamada definidas em [Dataverse MCP](dataverse-mcp.md).

Fontes oficiais consultadas em 21/09/2026. A integração prepara conexões e requer validação autenticada no ambiente antes de ser considerada operacional.
