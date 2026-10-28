# MDCC Agent Suite para Visual Studio Code e Claude Code

Conjunto de agentes personalizados para consultar, arquitetar, diagnosticar, planejar e validar soluções de **Microsoft Dynamics 365 Contact Center** e **Customer Service** dentro do VS Code (GitHub Copilot) e do Claude Code.

Consulte o [changelog](CHANGELOG.md) para acompanhar a linha de alterações do projeto.

## Início rápido (qualquer usuário, qualquer ambiente)

```powershell
npm ci                                                   # dependências fixadas (Playwright)
npm run doctor                                           # o que falta nesta estação, sem rede e sem segredos
pwsh -NoProfile -File scripts/sync-mdcc-docs.ps1         # Contact Center + Customer Service + CIF
```

1. **Ambiente Dataverse**: defina a variável de usuário `MDCC_DATAVERSE_URL` com a URL base do ambiente (ex.: `https://contoso.crm4.dynamics.com`) **ou** copie `config/dataverse-mcp.example.json` para `config/dataverse-mcp.local.json` e cadastre seus ambientes (dev, test, prod) para alternar com `npm run mcp:select`. A URL é validada pela política de conexão; o login é OAuth interativo e nenhuma credencial é gravada.
2. **Cards de atividade (opcional)**: `scripts/set-jira-connection.ps1` para Jira Cloud ou `scripts/set-ado-connection.ps1` (`-UseAzureCli` para Entra ID sem PAT) para Azure DevOps.
3. **Uso**: no VS Code, selecione **MDCC Master**; no Claude Code, use `/mdcc-master <pergunta>` ou `/mdcc-card <ABC-123 | 4521 | sprint>`.

Rode `npm run doctor` de novo até não haver bloqueios. Ele indica o comando exato para cada lacuna.

## Do card ao plano de implementação

`/mdcc-card` (Claude Code) ou o **MDCC Delivery Planner** (VS Code) lê o card do Jira ou do Azure DevOps, classifica por módulo (canais e voz, roteamento, IVR/Copilot Studio, experiência do agente, supervisão, Customer Service, dados e integração, ALM), busca a abordagem documentada nos docs sincronizados, no Microsoft Learn e nos repositórios oficiais da Microsoft no GitHub, lê o estado atual do ambiente via Dataverse MCP (somente leitura) e entrega por card: abordagem recomendada e descartada, passos, testes, riscos, estimativa em faixa e matriz afirmação → fonte. Gravar a estimativa ou o plano no card só acontece por comando explícito, um card por chamada, com aprovação. Fluxo completo em `.github/instructions/work-items.instructions.md`.

## O que está incluído

| Agente | Função |
|---|---|
| **MDCC Master** | Orquestra pesquisa, arquitetura, troubleshooting e revisão adversarial. |
| **MDCC Researcher** | Pesquisa todos os `.md` sincronizados e valida no Microsoft Learn. É subagente interno. |
| **MDCC Architect** | Analisa topologias, integrações, segurança, ALM, escala e trade-offs. |
| **MDCC Troubleshooter** | Produz diagnóstico ordenado por evidência e menor risco. |
| **MDCC Dataverse Diagnostician** | Consulta o ambiente via Dataverse MCP usando somente ferramentas de leitura. |
| **MDCC Dataverse Remediator** | Executa `update_record` somente após autorização específica por chamada. |
| **MDCC Browser Diagnostician** | Observa e reproduz problemas de interface com Playwright em sessão isolada e não produtiva. |
| **MDCC Delivery Planner** | Converte cards do Jira ou Azure DevOps em planos de implementação fundamentados. Somente leitura nos cards. |
| **MDCC Validator** | Bloqueia caminhos inventados, confusão de produto e afirmações sem fonte. É subagente interno. |

## Arquitetura de fundamentação

```text
Pergunta no VS Code
        │
        ▼
   MDCC Master
   ├── MDCC Researcher ──► .reference/.../{contact-center,shared}/**/*.md
   │                         └── Microsoft Learn ao vivo
   ├── MDCC Architect
   ├── MDCC Troubleshooter
   ├── MDCC Dataverse Diagnostician ──► Dataverse MCP (somente leitura)
   ├── MDCC Browser Diagnostician ────► Playwright MCP (UI, somente observação)
   ├── MDCC Delivery Planner ─────────► Jira MCP / Azure DevOps MCP (cards, leitura)
   └── MDCC Validator
        │
        ▼
Resposta com evidência, riscos e confiança

Nova sessão + identidade dedicada + aprovação por chamada
        └── MDCC Dataverse Remediator ──► update_record autorizado
```

A documentação não é tratada como treinamento permanente. Ela é clonada e atualizada localmente para ser pesquisada a cada interação. Questões sensíveis a mudanças são verificadas novamente no Microsoft Learn.

Todos os agentes herdam uma política única com cinco princípios verificáveis: Responsabilidade Extrema, Anti-Sycophancy, Profundidade verificável sem exposição de cadeia de pensamento privada, enriquecimento de input raso e Obsessão pelo objetivo. A política exige critérios de sucesso, pressupostos explícitos, matriz afirmação → fonte, riscos e testes; objetivo e persistência nunca ampliam autorização.

## Pré-requisitos

- Visual Studio Code atualizado;
- GitHub Copilot Chat com suporte a agentes;
- Git instalado;
- acesso à internet para GitHub e Microsoft Learn;
- PowerShell 7 (`pwsh`) em todas as plataformas para validações e build;
- Node.js 22, 24 ou 26 e npm para Playwright;
- Bash + Python 3 são opcionais em Linux/macOS como alternativa apenas para sincronizar a documentação.

## Instalação

1. Copie todo o conteúdo deste pacote para a raiz do workspace.
2. Abra o workspace no VS Code.
   Em um clone Git sem `.vscode/mcp.json`, execute `npm run mcp:select -- --reset` antes das validações, ou crie o catálogo local e aplique o ambiente. O ZIP já inclui a conexão genérica.
3. Execute `Terminal > Run Task > MDCC: Sync official documentation`.
4. Confirme a criação de:
   - `.reference/dynamics-365-contact-center/contact-center`;
   - `.reference/dynamics-365-contact-center/shared`;
   - `.reference/source-manifest.json`;
   - `.reference/mdcc-doc-index.json`.
5. Abra o Chat do Copilot e selecione **MDCC Master** na lista de agentes.
6. Execute `Terminal > Run Task > MDCC: Validate agent context` para comprovar que todos os agentes herdaram a política e que o índice inclui conteúdo compartilhado.
7. Para diagnóstico de interface, execute **MDCC: Install Playwright dependencies** e **MDCC: Validate Playwright guardrails**.

O VS Code reconhece agentes de workspace em `.github/agents/*.agent.md`.

## Atualização das fontes

Execute novamente a task **MDCC: Sync official documentation**. O script:

- sincroniza `MicrosoftDocs/dynamics-365-contact-center` e, por sparse checkout, `ce/customer-service` e `ce/channel-integration-framework` de `MicrosoftDocs/dynamics-365-customer-engagement` (use `-SkipCustomerService` para só Contact Center);
- atualiza o branch `main` com `fetch` e `reset`;
- inclui no índice todos os arquivos `.md` abaixo de `contact-center` e `shared`, com rastreamento de includes locais;
- grava commit, data e quantidade de arquivos;
- gera um índice de títulos e metadados para auditoria.

Execução manual no Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-mdcc-docs.ps1
```

Linux/macOS:

```bash
./scripts/sync-mdcc-docs.sh
```

## Como usar

Exemplos:

```text
Analise por que uma chamada de voz fica muda antes de chegar ao IVR do Copilot Studio.
```

```text
Desenhe uma topologia em que voz chega por operadora/Teams Phone e WhatsApp por ACS. Avalie conflito, licenciamento, segurança e operação.
```

```text
Valide se esta funcionalidade é nativa e mostre exatamente a fonte oficial: notificar supervisor por sentimento negativo.
```

## Limitações deliberadas

- O agente não pode garantir erro zero; ele reduz o risco por validação documental e revisão adversarial.
- O Microsoft Learn pode mudar depois da última sincronização local. Por isso caminhos de interface e disponibilidade devem ser validados ao vivo.
- Algumas páginas do Contact Center reutilizam conteúdo do Dynamics 365 Customer Service. O agente deve avaliar contexto, e não rejeitar automaticamente essas páginas.
- Ferramentas declaradas no frontmatter que não existirem na instalação do VS Code são ignoradas pelo próprio VS Code.
- A validação Playwright cobre a interface observada; não comprova isoladamente telefonia, roteamento ou backend.

## Playwright

O projeto inclui Playwright Test e o servidor MCP oficial com versões fixadas e lockfile. O agente **MDCC Browser Diagnostician** usa um contexto isolado para observar uma origem HTTPS aprovada em UAT/sandbox. O usuário faz SSO/MFA diretamente no navegador; credenciais, cookies e estado autenticado não são versionados.

Os binários Chromium e `node_modules` não entram no ZIP: instale-os de forma reproduzível pela task **MDCC: Install Playwright dependencies**. Ações que salvam, enviam, publicam, ativam, atribuem ou excluem permanecem fora do perfil padrão e inelegíveis para autoaprovação.

Consulte `docs/playwright-mdcc.md` para o preflight de ambiente, teste smoke somente leitura, isolamento entre clientes e limites de evidência.

## Dataverse MCP

O [guia de validação do ambiente](docs/dataverse-environment-validation.md) consolida arquitetura, OAuth interativo, limites de Client Secret e evidências de conexão. Execute `npm run mcp:preflight` para verificar o ambiente ativo e `npm run mcp:probe` para testar MCP GA com metadados em development/test no Windows. O probe usa o proxy oficial já instalado e pode exigir login interativo; seu resultado não comprova identidade/roles nem saúde funcional do MDCC.

### Ambientes pré-definidos

Edite apenas `activeEnvironment` (ou a URL correspondente) em `config/dataverse-mcp.local.json` e execute **MDCC: Apply predefined MCP environment** ou `npm run mcp:select`. O comando prepara a conexão HTTP de `dataverse-mdcc`; reinicie o servidor e confirme host, tenant e identidade no OAuth. Consulte o [guia de ambientes](docs/predefined-environments.md) e a [análise da pasta VS_Code](docs/vs-code-integration-review.md).

O catálogo e `.vscode/mcp.json` são locais e ignorados pelo Git. A fonte genérica é `config/mcp.template.json`; o ZIP sempre recebe esse template, sem os ambientes de clientes. Instalações novas podem copiar `config/dataverse-mcp.example.json` para o catálogo local. A seleção não habilita MCP nem concede permissões no ambiente.

Para selecionar o ambiente por uma interface visual, execute **MDCC: Configure customer MCP environment**. A página local valida a URL, mostra o endpoint `/api/mcp` normalizado e permite copiá-lo para o catálogo local e aplicá-lo pela task **MDCC: Apply predefined MCP environment**. Ela não grava o endpoint no projeto e não recebe credenciais. Consulte `docs/mcp-environment-configurator.md`.

O template inclui uma única conexão Dataverse parametrizada. Para GitHub Copilot no VS Code, o baseline oficial usa HTTP direto `/api/mcp`. No modo genérico, o endpoint é solicitado em runtime; no modo de presets, ele é materializado somente no arquivo local. A autenticação OAuth é tratada pelo VS Code; nomes de cliente e URLs fixas não entram no template ou em arquivos versionados, e credenciais nunca entram nos arquivos de configuração.

No modo genérico com input, antes de iniciar o servidor execute **MDCC: Prepare customer Dataverse MCP connection**. A task aceita a URL base ou o endpoint, normaliza para `/api/mcp`, valida HTTPS/host/caminho e não persiste o valor. Depois, inicie `dataverse-mdcc`, informe exatamente o endpoint validado e confirme o ambiente no prompt de confiança.

Ao trocar de cliente, pare o servidor, encerre a sessão, invalide aprovações anteriores e repita a preparação e a confirmação de identidade/roles. Não adicione aliases de clientes ao arquivo MCP.

Há dois perfis operacionais:

- **diagnóstico:** `search`, `search_data`, `read_query` e `describe`;
- **remediação:** as mesmas leituras mais `update_record`, sempre com autorização explícita para uma única chamada.

Criação, exclusão, mudança de esquema, skills, upload, download e preview permanecem bloqueados por padrão. Consulte `docs/dataverse-mcp.md` para configuração, roles, fluxo de aprovação, auditoria e extensão segura.

O Master não delega remediação no contexto de diagnóstico. A escrita só pode começar em nova sessão e contexto de credenciais Windows, com identidade Entra dedicada e role mínima. Um perfil ou nome de agente diferente não prova isolamento OAuth.

Em produção, o workspace sozinho não garante aprovação humana se o usuário habilitar Bypass/Autopilot. A remediação requer política organizacional que bloqueie esses modos e mantenha ferramentas mutantes inelegíveis para autoaprovação. O uso externo também pode consumir Copilot Credits conforme licença e data documentadas pela Microsoft.

Valide os controles após qualquer alteração:

```powershell
pwsh -NoProfile -File .\scripts\test-dataverse-mcp-guardrails.ps1
pwsh -NoProfile -File .\scripts\test-playwright-guardrails.ps1
npm run mcp:configure:test
```

## Jira e Azure DevOps

Dois servidores MCP locais, sem dependências externas, com a mesma postura: leitura livre, escrita mínima (campos, comentário, estado) em um card por chamada, sem criar ou excluir, aprovação manual em cada escrita e auditoria local sem valores. Credenciais ficam fora do repositório (DPAPI no Windows, variáveis de ambiente ou Entra ID via Azure CLI no caso do Azure DevOps). Detalhes em `docs/jira-mcp.md` e `docs/ado-mcp.md`.

## Visual Studio 2026

Requer Visual Studio 2026 18.4 ou superior com GitHub Copilot. O Visual Studio lê os agentes de `.github/agents/*.agent.md` na raiz do repositório; os agentes declaram também os nomes de ferramentas de leitura do Visual Studio (`code_search`, `readfile`, `find_references`, `getwebpages`), que o VS Code ignora.

```powershell
npm run vs:install
```

O comando gera `.vs\mcp.json` (por usuário, fora do Git) com `dataverse-mdcc` (launcher do proxy oficial, perfil diagnosis), `jira-mdcc`, `ado-mdcc` e, se `MDCC_PLAYWRIGHT_ORIGIN` estiver definida, `playwright-mdcc`, e faz o handshake local dos servidores. Depois, abra a pasta (**File > Open > Folder**), escolha **MDCC Master** no seletor de agentes do Copilot Chat e habilite as ferramentas MCP no painel **Tools**. No Visual Studio, subagentes e handoffs do VS Code não são orquestrados automaticamente: chame `@MDCC Researcher`, `@MDCC Delivery Planner` e os demais diretamente quando precisar.

## Claude Code

`.mcp.json` registra `dataverse-mdcc` (via `tools/dataverse-mcp/launch.mjs`, que resolve o ambiente por `MDCC_DATAVERSE_URL` ou pelo catálogo local e localiza o proxy oficial `@microsoft/dataverse` em Windows, Linux ou macOS), `playwright-mdcc`, `jira-mdcc` e `ado-mdcc`. Ferramentas mutantes do Dataverse são negadas e as de Jira/Azure DevOps pedem aprovação (`.claude/settings.json`). Skills: `/mdcc-master` e `/mdcc-card`.

## Fontes configuradas

- Catálogo canônico: `config/mdcc-sources.json`, com 78 URLs únicas organizadas por tema — 58 do anexo inicial, 12 fontes oficiais de Dataverse MCP, segurança, policies e configuração do VS Code, e 8 de Channel Integration Framework, repositórios de documentação e APIs de work tracking (Azure DevOps e Jira).
- Base versionada primária: `MicrosoftDocs/dynamics-365-contact-center`, diretórios `contact-center` e `shared`; base complementar: `MicrosoftDocs/dynamics-365-customer-engagement`, diretórios `ce/customer-service` e `ce/channel-integration-framework`.
- Microsoft Learn em `en-us` e `pt-br`: Dynamics 365, Contact Center, Customer Service, Customer Insights, Customer Voice e planos de lançamentos.
- Fontes oficiais complementares: Teams Phone/Direct Routing, Azure Communication Services, Power Platform, Dataverse, Power Apps, Power Automate, Copilot Studio e repositórios Microsoft/MicrosoftGraph no GitHub.
- Fontes somente para descoberta: Microsoft Q&A, Dynamics Community, Tech Community, YouTube e amostras PnP. Elas não podem sustentar afirmações técnicas sem confirmação em documentação oficial elegível.
- Formato de agentes do VS Code: `.github/agents/*.agent.md`.

As URLs do catálogo foram normalizadas sem `utm_source=chatgpt.com`. Parâmetros funcionais, como `pivots=platform-web`, foram preservados. A lista amplia a pesquisa ao vivo; o comando de sincronização local continua baixando somente a base primária do Dynamics 365 Contact Center.

## Validação

Use `tests/acceptance-scenarios.md` para testar os agentes contra casos propensos a respostas incorretas ou caminhos administrativos inventados.

Execute também:

```powershell
npm test                 # testes Node: configurador, presets, diagnóstico, pacote, Jira, Azure DevOps, doctor
npm run test:guardrails  # guardrails Dataverse/Playwright e contexto dos agentes
```

O workflow `.github/workflows/ci.yml` roda o mesmo conjunto, mais o build do pacote, a cada push e pull request.

O artefato `mdcc-vscode-agent-suite.zip` é gerado por **MDCC: Build verified package**. O build inclui um manifesto SHA-256 e falha se agentes, instruções, políticas, scripts ou testes obrigatórios estiverem ausentes; não distribua um ZIP montado manualmente.

