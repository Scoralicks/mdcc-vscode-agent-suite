# MDCC Agent Suite para Visual Studio Code

Conjunto de agentes personalizados para consultar, arquitetar, diagnosticar e validar soluções de **Microsoft Dynamics 365 Contact Center** dentro do VS Code.

Consulte o [changelog](CHANGELOG.md) para acompanhar a linha de alterações do projeto.

## O que está incluído

| Agente | Função |
|---|---|
| **MDCC Master** | Orquestra pesquisa, arquitetura, troubleshooting e revisão adversarial. |
| **MDCC Researcher** | Pesquisa todos os `.md` sincronizados e valida no Microsoft Learn. É subagente interno. |
| **MDCC Architect** | Analisa topologias, integrações, segurança, ALM, escala e trade-offs. |
| **MDCC Troubleshooter** | Produz diagnóstico ordenado por evidência e menor risco. |
| **MDCC Dataverse Diagnostician** | Consulta o ambiente via Dataverse MCP usando somente ferramentas de leitura. |
| **MDCC Dataverse Remediator** | Executa `update_record` somente após autorização específica por chamada. |
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
   ├── MDCC Dataverse Remediator ─────► Dataverse MCP (update autorizado)
   └── MDCC Validator
        │
        ▼
Resposta com evidência, riscos e confiança
```

A documentação não é tratada como treinamento permanente. Ela é clonada e atualizada localmente para ser pesquisada a cada interação. Questões sensíveis a mudanças são verificadas novamente no Microsoft Learn.

Todos os agentes herdam uma política única com cinco princípios verificáveis: Responsabilidade Extrema, Anti-Sycophancy, Profundidade verificável sem exposição de cadeia de pensamento privada, enriquecimento de input raso e Obsessão pelo objetivo. A política exige critérios de sucesso, pressupostos explícitos, matriz afirmação → fonte, riscos e testes; objetivo e persistência nunca ampliam autorização.

## Pré-requisitos

- Visual Studio Code atualizado;
- GitHub Copilot Chat com suporte a agentes;
- Git instalado;
- acesso à internet para GitHub e Microsoft Learn;
- PowerShell 7 (`pwsh`) em todas as plataformas para validações e build;
- Bash + Python 3 são opcionais em Linux/macOS como alternativa apenas para sincronizar a documentação.

## Instalação

1. Copie todo o conteúdo deste pacote para a raiz do workspace.
2. Abra o workspace no VS Code.
3. Execute `Terminal > Run Task > MDCC: Sync official documentation`.
4. Confirme a criação de:
   - `.reference/dynamics-365-contact-center/contact-center`;
   - `.reference/dynamics-365-contact-center/shared`;
   - `.reference/source-manifest.json`;
   - `.reference/mdcc-doc-index.json`.
5. Abra o Chat do Copilot e selecione **MDCC Master** na lista de agentes.
6. Execute `Terminal > Run Task > MDCC: Validate agent context` para comprovar que todos os agentes herdaram a política e que o índice inclui conteúdo compartilhado.

O VS Code reconhece agentes de workspace em `.github/agents/*.agent.md`.

## Atualização das fontes

Execute novamente a task **MDCC: Sync official documentation**. O script:

- atualiza o branch `main` com `fetch` e `reset`;
- inclui no índice todos os arquivos `.md` abaixo de `contact-center` e `shared`, com rastreamento de includes locais;
- grava commit, data e quantidade de arquivos;
- gera um índice de títulos e metadados para auditoria.

Execução manual no Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-mdcc-docs.ps1
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

## Dataverse MCP

O workspace inclui uma conexão MCP editável em `.vscode/mcp.json`. Para GitHub Copilot no VS Code, o baseline oficial usa HTTP direto `/api/mcp`. O endpoint é solicitado em runtime e a autenticação OAuth é tratada pelo armazenamento seguro do VS Code; credenciais não devem ser colocadas no chat, em `.env` ou em arquivos versionados.

Antes de iniciar o servidor, execute **MDCC: Validate Dataverse MCP endpoint**. O input seguro armazena o valor, mas a validação de HTTPS, host e caminho GA é feita pela task e pela confirmação humana no prompt de confiança.

Há dois perfis operacionais:

- **diagnóstico:** `search`, `search_data`, `read_query` e `describe`;
- **remediação:** as mesmas leituras mais `update_record`, sempre com autorização explícita para uma única chamada.

Criação, exclusão, mudança de esquema, skills, upload, download e preview permanecem bloqueados por padrão. Consulte `docs/dataverse-mcp.md` para configuração, roles, fluxo de aprovação, auditoria e extensão segura.

O Master não delega remediação no contexto de diagnóstico. A escrita só pode começar em nova sessão e contexto de credenciais Windows, com identidade Entra dedicada e role mínima. Um perfil ou nome de agente diferente não prova isolamento OAuth.

Em produção, o workspace sozinho não garante aprovação humana se o usuário habilitar Bypass/Autopilot. A remediação requer política organizacional que bloqueie esses modos e mantenha ferramentas mutantes inelegíveis para autoaprovação. O uso externo também pode consumir Copilot Credits conforme licença e data documentadas pela Microsoft.

Valide os controles após qualquer alteração:

```powershell
pwsh -NoProfile -File .\scripts\test-dataverse-mcp-guardrails.ps1
```

## Fontes configuradas

- Catálogo canônico: `config/mdcc-sources.json`, com 70 URLs únicas organizadas por tema — 58 do anexo inicial e 12 fontes oficiais adicionais de Dataverse MCP, segurança, policies e configuração do VS Code.
- Base versionada primária: `MicrosoftDocs/dynamics-365-contact-center`, diretórios `contact-center` e `shared`.
- Microsoft Learn em `en-us` e `pt-br`: Dynamics 365, Contact Center, Customer Service, Customer Insights, Customer Voice e planos de lançamentos.
- Fontes oficiais complementares: Teams Phone/Direct Routing, Azure Communication Services, Power Platform, Dataverse, Power Apps, Power Automate, Copilot Studio e repositórios Microsoft/MicrosoftGraph no GitHub.
- Fontes somente para descoberta: Microsoft Q&A, Dynamics Community, Tech Community, YouTube e amostras PnP. Elas não podem sustentar afirmações técnicas sem confirmação em documentação oficial elegível.
- Formato de agentes do VS Code: `.github/agents/*.agent.md`.

As URLs do catálogo foram normalizadas sem `utm_source=chatgpt.com`. Parâmetros funcionais, como `pivots=platform-web`, foram preservados. A lista amplia a pesquisa ao vivo; o comando de sincronização local continua baixando somente a base primária do Dynamics 365 Contact Center.

## Validação

Use `tests/acceptance-scenarios.md` para testar os agentes contra casos propensos a respostas incorretas ou caminhos administrativos inventados.

Execute também:

```powershell
pwsh -NoProfile -File .\scripts\test-agent-context.ps1
pwsh -NoProfile -File .\scripts\test-dataverse-mcp-guardrails.ps1
```

O artefato `mdcc-vscode-agent-suite.zip` é gerado por **MDCC: Build verified package**. O build inclui um manifesto SHA-256 e falha se agentes, instruções, políticas, scripts ou testes obrigatórios estiverem ausentes; não distribua um ZIP montado manualmente.
