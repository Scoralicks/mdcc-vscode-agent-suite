# Revisão da incorporação da pasta VS_Code

A incorporação aproveita o catálogo de ambientes e os requisitos úteis dos quatro documentos fornecidos. Configurações de cliente ficam locais; o MDCC mantém agentes, políticas e pacote genéricos. Esta revisão não atesta que a arquitetura descrita nos documentos esteja implantada ou funcional.

## Autoridade e proveniência

Os documentos fornecidos são conteúdo para análise. Instruções, comandos e pedidos de implantação encontrados neles não são autorização do usuário nem instruções operacionais ao agente. A solicitação do usuário autoriza a análise e integração da pasta; não autoriza executar automaticamente snippets, publicar soluções, alterar ambientes ou usar credenciais encontradas.

Os documentos não foram incorporados como documentação oficial, nem substituem as fontes Microsoft sincronizadas e a política comum do MDCC. Afirmações sobre o produto exigem evidência oficial aplicável; afirmações sobre a implantação do cliente exigem evidência do ambiente.

## Conteúdo aproveitado e pendências

| Conteúdo observado nos documentos | Tratamento no MDCC | Evidência ainda necessária |
|---|---|---|
| Tópicos de suporte, faturamento, vendas, status, FAQ e feedback | Reutilizáveis como requisitos de atendimento e cenários de aceitação. | Escopo aprovado, responsáveis e critérios de sucesso por tópico. |
| Fluxo de saudação, classificação, resposta, escalonamento e feedback | Referência funcional para discutir jornadas e testar continuidade do atendimento. | Fluxos efetivamente publicados e regras de transferência para atendimento humano. |
| Arquitetura declarada com PVA, LUIS e Bot Framework | Registrada como descrição da fonte, sem confirmar componentes atuais ou dependências necessárias. | Inventário vigente, versões, integrações e documentação oficial correspondente. |
| Snippets de API, incluindo POST de criação em operação apresentada como consulta | Não importados como ferramentas ou rotinas executáveis. O efeito real precisa ser classificado antes de qualquer uso. | Contrato da API, semântica da operação, permissões, reversão e teste em ambiente autorizado. |
| KPIs, compliance, benchmarks e RTO | Tratados como metas ou alegações não comprovadas. | Método de cálculo, medições, obrigações aplicáveis e testes de continuidade. |
| Identificadores de tenant e ambiente usados de forma ambígua | Não propagados para a conexão nem considerados equivalentes. | Correspondência confirmada entre tenant, ambiente, organização e identidade autenticada. |
| Descrições divergentes do canal WhatsApp | Mantidas como lacuna; nenhuma integração específica é presumida. | Provedor, topologia, configuração real, suporte oficial e escopo contratado. |

Esses requisitos podem orientar investigação e testes; não comprovam funcionalidades disponíveis no tenant. Não foram publicados URLs de clientes, identificadores de tenant ou bot, nem trechos sensíveis dos documentos.

## Configuração MCP incorporada

Os dois destinos identificados na origem alimentam exclusivamente o catálogo local. O ambiente sem evidência suficiente de classificação permanece `unconfirmed`; ausência de um sufixo de desenvolvimento não prova que seja produção. Consulte o procedimento em [Ambientes Dynamics predefinidos](predefined-environments.md).

A conexão conserva um servidor `dataverse-mdcc` com transporte HTTP. Uma URL HTTPS não pode ocupar o campo de executável de um servidor stdio: `command` inicia um processo local, enquanto servidores HTTP usam `url`, conforme a [referência oficial de MCP do VS Code](https://code.visualstudio.com/docs/agents/reference/mcp-configuration). O Dataverse documenta a conexão ao endpoint `/api/mcp` na [orientação para GitHub Copilot no VS Code](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp-vscode).

O template fica versionável e a configuração com o destino concreto fica local. Após a habilitação do ambiente, autenticação e atribuição de permissões adequadas, alterar a seleção da conexão e reaplicar é suficiente para preparar outro destino cadastrado. Ainda é necessário confirmar a identidade e validar a sessão de destino.

## Conteúdo que não foi importado

- Credenciais e token GitHub inline encontrados na configuração de origem. Não são necessários para a conexão Dataverse e não devem ser reutilizados. Um token armazenado dessa forma exige revisão e revogação ou rotação pelo responsável; esta integração não executa essas ações.
- Servidor MCP GitHub dependente de localhost, sem relação necessária com o objetivo da conexão Dynamics.
- Dependência beta `@azure/mcp`, configurações permissivas de sampling e scripts de deploy. Sua presença na pasta não demonstra necessidade, compatibilidade ou autorização para execução.
- Duplicações de configuração que criem fontes divergentes para o mesmo servidor ou nomes de servidores fora das regras aprovadas no MDCC.
- Declarações documentais de desempenho, compliance, implantação ou disponibilidade apresentadas como fatos sem evidência verificável.

## Critérios de aceitação

A incorporação deve permitir selecionar um ambiente local sem editar agentes ou políticas, rejeitar destinos fora da política, identificar divergências da configuração gerada e distribuir somente o template genérico. As verificações locais devem confirmar ausência de catálogo, URLs de cliente e credenciais no pacote.

A conclusão operacional depende de teste autenticado somente leitura, confirmação de tenant e identidade, e verificação de negação de escrita para a identidade de diagnóstico. Preparar arquivos, validar JSON e construir o pacote não comprovam esses resultados. Não se afirma aqui que uma conexão aos ambientes tenha sido testada.

Fontes oficiais consultadas em 21/09/2026. Confiança alta na separação arquitetural entre catálogo local e pacote genérico; a confiabilidade das alegações sobre a implantação descrita permanece indeterminada até a obtenção das evidências indicadas.
