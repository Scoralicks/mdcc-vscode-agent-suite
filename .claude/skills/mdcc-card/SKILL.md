---
name: mdcc-card
description: Transforma um card do Jira (ABC-123) ou do Azure DevOps (id numérico), uma sprint ou uma consulta JQL/WIQL em plano de implementação MDCC fundamentado no Microsoft Learn, no GitHub oficial e no ambiente Dataverse ativo. Use para refinamento, planejamento de sprint e estimativa.
argument-hint: ABC-123 | 4521 | "sprint atual do projeto X" | JQL/WIQL
---

Você roda na sessão principal e orquestra o fluxo de `.github/instructions/work-items.instructions.md`.

1. Leia `.github/instructions/mdcc-common.instructions.md`, `.github/instructions/work-items.instructions.md` e `.github/agents/mdcc-delivery-planner.agent.md`.
2. Confirme que `.reference/mdcc-doc-index.json` existe e tem menos de 14 dias; se não, rode `pwsh -NoProfile -File scripts/sync-mdcc-docs.ps1`. Se Jira ou Azure DevOps não responderem, rode `npm run doctor` e indique o script de configuração.
3. Acione `mdcc-delivery-planner` com o card ou a consulta e o contexto da conversa. Em paralelo, quando útil, acione `mdcc-researcher` para capacidades específicas.
4. Se o retorno listar **Pendências para a sessão principal**, acione `mdcc-dataverse-diagnostician` (somente leitura) para o estado do ambiente e `mdcc-architect` para decisões de desenho.
5. Acione `mdcc-validator` com o plano e as evidências. Se FAIL, corrija e valide de novo.
6. Entregue o plano sintetizado. Só grave no card (estimativa, comentário, estado) se o usuário pedir explicitamente, seguindo as regras de escrita do sistema de origem, um card por chamada.

Nunca acione `mdcc-dataverse-remediator` a partir deste fluxo.

Solicitação: $ARGUMENTS
