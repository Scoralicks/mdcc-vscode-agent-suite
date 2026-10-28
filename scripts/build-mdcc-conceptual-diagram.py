"""Gera o Diagrama Conceitual do Dynamics 365 Contact Center (draw.io editável).

Reaproveita o template do Customer Service (estilos, camadas, logo e ícones de canal).
Uso: python scripts/build-mdcc-conceptual-diagram.py <template.drawio.xml> <saida.drawio> [pt|en]
O idioma "en" usa o glossário scripts/mdcc-diagram-i18n-en.json (chave = rótulo em português).
"""
import json
import os
import re
import sys
from xml.sax.saxutils import escape

TEMPLATE, OUT = sys.argv[1], sys.argv[2]
LANG = sys.argv[3] if len(sys.argv) > 3 else "pt"
tpl = open(TEMPLATE, encoding="utf-8").read()
I18N = {}
if LANG != "pt":
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "mdcc-diagram-i18n-%s.json" % LANG), encoding="utf-8") as f:
        I18N = json.load(f)


def image_of(cell_id):
    m = re.search(r'id="%s"[^>]*?image=(data:image/[^;"]+)' % re.escape(cell_id), tpl)
    return m.group(1) if m else None


ICON = {
    "email": image_of("HnwzWjyziMIptjzow982-10"),
    "phone": image_of("HnwzWjyziMIptjzow982-9"),
    "teams": image_of("HnwzWjyziMIptjzow982-11"),
    "chat": image_of("HnwzWjyziMIptjzow982-8"),
    "sms": image_of("HnwzWjyziMIptjzow982-12"),
    "social1": image_of("HnwzWjyziMIptjzow982-13"),
    "social2": image_of("HnwzWjyziMIptjzow982-14"),
    "social3": image_of("HnwzWjyziMIptjzow982-15"),
}
LOGO = image_of("UepNrXPDkmMAaelb-V-0-59")

FONT = ("fontFamily=Segoe UI;fontSource=proxy%3Furl%3Dhttp%253A%252F%252Fc.s-microsoft.com"
        "%252Fstatic%252Ffonts%252Fsegoe-ui%252Fwest-european%252Fnormal%252Flatest.ttf;")
FONT_F = FONT.replace("%", "%%")  # para estilos formatados com %
S_BAND = ("rounded=1;absoluteArcSize=1;arcSize=24;whiteSpace=wrap;html=1;fontSize=32;verticalAlign=middle;"
          "fontStyle=1;strokeWidth=2;glass=0;shadow=0;" + FONT_F + "strokeColor=%s;fillColor=%s;textOpacity=50;")
S_GROUP = ("rounded=1;absoluteArcSize=1;arcSize=16;whiteSpace=wrap;html=1;fontSize=14;verticalAlign=top;"
           "fontStyle=1;strokeWidth=1;glass=0;shadow=0;" + FONT_F + "strokeColor=%s;fillColor=none;dashed=1;")
S_ITEM = ("rounded=0;whiteSpace=wrap;html=1;" + FONT + "fontSize=11;strokeWidth=1;fontStyle=0;"
          "fillColor=#FFFFFF;strokeColor=none;glass=0;")
S_STEP = ("shape=step;perimeter=stepPerimeter;whiteSpace=wrap;html=1;fixedSize=1;fontSize=10;fillColor=%s;"
          "strokeColor=none;size=10;" + FONT_F + "rounded=0;shadow=0;fontColor=#FFFFFF;")
S_ICON = "shape=image;verticalLabelPosition=bottom;verticalAlign=top;aspect=fixed;imageAspect=0;image=%s;opacity=50;"
S_OVERLAY = ("text;html=1;strokeColor=#FFFFFF;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;"
             "rounded=1;fontSize=24;opacity=80;" + FONT + "fontColor=#FFFFFF;spacing=13;fontStyle=0;")

cells = []
_n = [0]


def nid(prefix):
    _n[0] += 1
    return "mdcc-%s-%d" % (prefix, _n[0])


def cell(layer, style, x, y, w, h, value="", prefix="c"):
    cells.append('<mxCell id="%s" value="%s" style="%s" parent="%s" vertex="1">'
                 '<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry" /></mxCell>'
                 % (nid(prefix), escape(value, {'"': "&quot;"}), style, layer, x, y, w, h))


L_FEAT, L_DET, L_DET2, L_OVER, L_TITLE = "mdcc-layer-features", "mdcc-layer-details", "mdcc-layer-details2", "mdcc-layer-overlay", "mdcc-layer-title"

ITEM_H, GAP, PAD, TITLE_H = 30, 6, 10, 34


def html(text):
    """'a|b|c' -> primeira linha + lista com marcadores; '\n' -> quebra."""
    parts = text.split("|")
    head = escape(parts[0]).replace("\n", "<br>")
    if len(parts) == 1:
        return head
    bullets = "<br>".join("- " + escape(p) for p in parts[1:])
    return '%s<br><font style="font-size: 9px;">%s</font>' % (head, bullets)


def item_rows(it):
    return it[2] if isinstance(it, tuple) and len(it) > 2 else 1


def layout_items(items, cols):
    """Empacota itens (texto | (texto, colspan[, rowspan])) numa grade; retorna posições e nº de linhas."""
    occ, pos = {}, []
    r = c = 0
    for it in items:
        cs = it[1] if isinstance(it, tuple) else 1
        rs = item_rows(it)
        while True:
            if c + cs > cols:
                r, c = r + 1, 0
                continue
            if all((r + i, c + j) not in occ for i in range(rs) for j in range(cs)):
                break
            c += 1
        for i in range(rs):
            for j in range(cs):
                occ[(r + i, c + j)] = True
        pos.append((r, c, cs, rs, it[0] if isinstance(it, tuple) else it))
        c += cs
    rows = max(k[0] for k in occ) + 1 if occ else 0
    return pos, rows


def group_height(g):
    _, rows = layout_items(g["items"], g["cols"])
    return TITLE_H + rows * ITEM_H + (rows - 1) * GAP + PAD


def draw_group(g, x, y, w, h, stroke="#999999"):
    style = S_GROUP % stroke + ("align=left;spacingLeft=10;" if g.get("steps") else "")
    cell(L_DET, style, x, y, w, h, g["title"], "grp")
    if g.get("steps"):
        sw = 92
        sx = x + w - PAD - sw * len(g["steps"])
        for i, s in enumerate(g["steps"]):
            cell(L_DET, S_STEP % g["step_color"], sx + i * sw, y + 7, sw + 2, 20, s, "stp")
    cols = g["cols"]
    left = PAD + (26 if g.get("icons") else 0)
    cw = (w - left - PAD - (cols - 1) * GAP) / cols
    pos, _ = layout_items(g["items"], cols)
    for idx, (r, c, cs, rs, text) in enumerate(pos):
        ix = x + left + c * (cw + GAP)
        iy = y + TITLE_H + r * (ITEM_H + GAP)
        cell(L_DET2, S_ITEM, ix, iy, cs * cw + (cs - 1) * GAP, rs * ITEM_H + (rs - 1) * GAP, html(text), "itm")
        icon = g.get("icons", {}).get(idx)
        if icon:
            keys = icon if isinstance(icon, list) else [icon]
            if len(keys) == 1:
                cell(L_DET2, S_ICON % ICON[keys[0]], x + 8, iy + 4, 21, 21, "", "ico")
            else:
                for k, (dx, dy) in zip(keys, [(5, 0), (0, 9), (11, 9)]):
                    cell(L_DET2, S_ICON % ICON[k], x + 6 + dx, iy + 2 + dy, 13, 13, "", "ico")


def draw_band(x, y, w, groups, stroke, fill, label, group_stroke="#999999"):
    """groups: lista de colunas; cada coluna é uma lista de grupos empilhados, com largura relativa 'w'."""
    total = sum(col["w"] for col in groups)
    inner_w = w - 2 * PAD - (len(groups) - 1) * PAD
    col_h = []
    for col in groups:
        col_h.append(sum(group_height(g) for g in col["stack"]) + (len(col["stack"]) - 1) * PAD)
    h = max(col_h) + 2 * PAD
    cell(L_FEAT, S_BAND % (stroke, fill), x, y, w, h, "", "band")
    cell(L_OVER, S_OVERLAY, x, y, w, h, label, "ovl")
    cx = x + PAD
    for col, ch in zip(groups, col_h):
        cw = inner_w * col["w"] / total
        gy = y + PAD
        stack = col["stack"]
        extra = (h - 2 * PAD - ch)
        for i, g in enumerate(stack):
            gh = group_height(g) + (extra if i == len(stack) - 1 else 0)
            draw_group(g, cx, gy, cw, gh, group_stroke)
            gy += gh + PAD
        cx += cw + PAD
    return h


def tr(text):
    return I18N.get(text, text)


def tr_item(it):
    # Itens passam por html(), que já escapa: o glossário usa "&amp;" e aqui volta a "&".
    if isinstance(it, tuple):
        return (tr(it[0]).replace("&amp;", "&"),) + it[1:]
    return tr(it).replace("&amp;", "&")


def G(title, cols, items, **kw):
    d = {"title": tr(title), "cols": cols, "items": [tr_item(i) for i in items]}
    d.update(kw)
    if "steps" in d:
        d["steps"] = [tr(s) for s in d["steps"]]
    return d


def C(w, *stack):
    return {"w": w, "stack": list(stack)}


# --------------------------------------------------------------------------- conteúdo
X0, Y0 = 0, 150
MAIN_W, RIGHT_W, SEP = 1500, 230, 10
RX = X0 + MAIN_W + SEP

y = Y0
# 1. Searching & Reporting
y += draw_band(X0, y, MAIN_W, [
    C(62, G("Searching", 6, ["Pesquisa de Registros\n(vincular / desvincular)", "Identificação Automática\ndo Cliente",
                             "Pesquisa de Transcrições", "Pesquisa no Discador\nde Saída (preview)",
                             "Pesquisa de Conhecimento\nIntegrada", "Visões e Filtros\npersonalizados do Inbox"])),
    C(38, G("Reporting", 4, ["Dashboards\nTempo Real", "Dashboards\nHistóricos", "Wallboard View", "Real-time Streaming\nAnalytics (preview)"])),
], "#FFFF33", "#FFFFCC", "Searching &amp; Reporting") + SEP

# 2. Clientes & Contexto
y += draw_band(X0, y, MAIN_W, [
    C(24, G("Accounts - Contas", 2, ["Tipo de Cliente", "Endereço(s)", "Linha do tempo\n(Timeline)", "Contatos Relacionados"])),
    C(24, G("Contacts - Contatos", 2, ["Detalhes Pessoais", "Forma Preferencial\nde Contato", "Linha do tempo\n(Timeline)", "Perfis Sociais\n(WhatsApp, Facebook...)"])),
    C(32, G("Contexto da Conversa", 3, ["Variáveis de Contexto", "Pesquisa Pré-conversa", "Autenticação do Cliente",
                                        "Localização do Visitante", "Contexto Personalizado\n(SDK / API)", "Consentimento\n(engajamento proativo)"])),
    C(20, G("Identificação &amp; Registro", 2, ["Identificar Cliente\n(ANI, e-mail, campos)", "Criar Registro\nna Conversa",
                                                "Casos Vinculados", "Notas da Conversa"])),
], "#B3FF66", "#E6FFCC", "Customers") + SEP

# 3. Atividades & Interações
y += draw_band(X0, y, MAIN_W, [
    C(40, G("Atividades Principais", 6, ["Emails", "Telefonemas", "SMS", "Compromissos", "Tarefas", "Notas"])),
    C(34, G("Conversation Records", 4, ["Conversa\n(Ongoing Conv.)", "Sessão", "Transcrição", "Gravação de\nChamada"])),
    C(26, G("Feedback Surveys", 3, ["Pós-conversa\n(Copilot Studio)", "Pós-chamada\n(Voz)", "Customer Voice"])),
], "#66FF66", "#CCFFCC", "Activities") + SEP

# 4. Canais, Voz & Roteamento Unificado
channels = G("Channels", 1, ["Voz", "Teams Phone", "Chat ao vivo", "Email", "SMS", "WhatsApp", "Facebook",
                             "Apple Messages", "LINE / WeChat", "Microsoft Teams", "Canal Personalizado\n(Direct Line / API)",
                             "Registros\n(Casos e entidades)"],
             icons={0: "phone", 1: "teams", 2: "chat", 3: "email", 4: "sms", 5: ["social1", "social2", "social3"],
                    9: "teams"})
voice = G("Canal de Voz &amp; Telefonia", 3, [
    "Azure Communication\nServices (ACS)", "Números de Telefone\n(trial / próprios)", "Bring Your Own\nCarrier (BYOC)",
    ("Teams Phone no Contact Center|Calling Plan|Direct Routing|Operator Connect", 2, 2),
    ("Encaminhar chamadas\ndo Teams p/ Contact Center", 1, 2),
    "Perfis de Entrada\ne de Saída", "Chamadas de Entrada", "Chamadas de Saída\n(discador)",
    "Agentes IVR\n(Copilot Studio)", "IVR Multilíngue", "Ações de Fallback\ndo IVR",
    "Real-time Voice\nAgents", "Integração com\nURA de terceiros", "Correio de Voz",
    "Callback Direto /\nCustomer-first", ("Gravação, Transcrição e\nTradução em tempo real", 2),
    "Transferir e Consultar\n(representante / Teams)", "Consulta com\nAgente de IA (preview)", "Música de Espera",
    "Bloqueio de Spam", "Chamadas de\nEmergência", "Mascaramento de\nVariáveis Sensíveis",
    "Desktop Companion\nApp", "Azure Virtual Desktop\n/ Citrix", "Uso de Chamadas\ne Preços",
], steps=["Entrada", "IVR", "Fila", "Atender", "Pós-chamada"], step_color="#D8ABFF")
routing = G("Unified Routing", 3, [
    ("Workstreams|Mensagens|Voz|Registros", 1, 2), "Regras de Classificação", "Regras Route-to-Queue",
    "Modelo Skill Finder (ML)", "Predição de Sentimento",
    "Estimativa de Esforço", "Roteamento por Intenção\n(Customer Intent Agent)", "Roteamento p/ Representante\nPreferencial",
    ("Filas|Mensagens|Voz|Registros|Avançadas", 1, 2),
    ("Métodos de Atribuição|Maior capacidade|Round robin|Mais ocioso|Personalizado", 1, 2),
    "Roteamento por\nHabilidades", "Bullseye Routing\n(preview)",
    "Overflow de Filas", "Horário de\nFuncionamento", "Roteamento\nbaseado em Turnos",
    "Perfis de Capacidade", "Presença do\nRepresentante", "Atribuição Automática\n/ Timeout",
    "Plug-in p/ registros\nnão-caso", "Diagnóstico de\nRoteamento",
], steps=["Classificar", "Rotear", "Atribuir"], step_color="#D8ABFF")
y += draw_band(X0, y, MAIN_W, [C(14, channels), C(46, voice), C(40, routing)],
               "#B266FF", "#F0DEFF", "Channels, Voice &amp; Unified Routing") + SEP

# 5. Copilot & Agentes de IA
y += draw_band(X0, y, MAIN_W, [
    C(26, G("Copilot p/ Representantes", 2, [
        "Resumo de Conversas\ne Casos", "Pergunte ao Copilot\n(Ask a question)", "Rascunho de Email",
        "Rascunho de Respostas\n(chat)", "Notas de Resolução", "Plugins de IA\nGenerativa (preview)",
        "Fontes de Conhecimento\nCopilot Studio", "Respostas Verbatim\nde Artigos"])),
    C(28, G("Contact Center Agents", 2, [
        "Customer Intent Agent", "Customer Knowledge\nManagement Agent", "Quality Assurance\nAgent",
        "Service Operations\nAgent", "Customer Assist\nAgent", "Autonomous Service\nAgents",
        "Playbooks de Orquestração\n(preview)", "Simulações com\nConversas de IA (preview)"])),
    C(24, G("Agentes de IA (Self-service)", 2, [
        "Agente Copilot Studio", "Agente Azure AI", "Variáveis de Contexto\np/ Agentes",
        "Escalonar p/\nRepresentante", "Transferir p/ Agente\nde IA", "Sessões e\nLicenciamento"])),
    C(22, G("Agent Hub &amp; Governança", 2, [
        "Agent Hub", "Planos de Rollout", "Agent Insights", "Agent Feed\n(supervisão de IA)",
        "Trust Center", "Responsible AI"])),
], "#00B3B3", "#D6F5F5", "Copilot &amp; AI Agents") + SEP

# 6. Conhecimento & Engajamento Proativo
y += draw_band(X0, y, MAIN_W, [
    C(36, G("Knowledge Articles", 4, [
        "Palavras-chave", "Envio p/\nAprovação", "Categorias", "Templates de Artigo",
        "Anexos", "Artigos Relacionados", "Versões", "Tradução",
        "Feedback e Avaliação", ("Artigos gerados por IA\n(Knowledge Mgmt Agent)", 2), "Editor Rich Text"],
        steps=["Autor", "Revisão", "Publicação"], step_color="#FF9EFF")),
    C(26, G("Knowledge Search", 2, [
        "Provedores de Pesquisa\nIntegrados", "Smart Assist\n(artigos e casos similares)",
        "Filtros de Pesquisa", "Enviar / Compartilhar\nArtigo", "Vincular / Desvincular",
        "Pesquisa em Portais"])),
    C(38, G("Proactive Engagement", 3, [
        "Proativo por Voz", "Proativo por Mensagens\n(SMS / WhatsApp)", "Agentes de IA\np/ Proativo",
        ("Modos de Discagem|Copilot|Progressivo|Preditivo|Preview", 1, 2), "Consentimento", "Resultados\n(Outcomes)",
        "APIs de Entrega\nProativa (CCaaS)", "Boas práticas e\nregulamentação"],
        steps=["Planejar", "Discar", "Resultado"], step_color="#FF9EFF")),
], "#FF66FF", "#FFDEFF", "Knowledge &amp; Proactive Engagement") + SEP

# 7. Workforce & Quality Management
y += draw_band(X0, y, MAIN_W, [
    C(62, G("Workforce Management", 6, [
        "Grupos de\nPlanejamento", "Previsão de Volume\n(Forecasting)", "Capacity Planning", "Planos de Turnos",
        "Auto Schedule", "Rotação de Turnos",
        "Shift Bidding", "Shift Swapping", "Folgas\n(time-off)", "Calendário do\nRepresentante",
        "Adherence Tracker", "Alertas Intraday\n(preview)"],
        steps=["Prever", "Planejar", "Agendar", "Aderir"], step_color="#B3B3FF")),
    C(38, G("Quality Management", 4, [
        "Critérios de\nAvaliação", "Planos de Avaliação", "Avaliação sob\nDemanda", "Quality Assurance\nAgent",
        "Gravação de Tela", "Quality & Coaching\nSkill", "Dashboard de\nQualidade",
        "Avaliações"],
        steps=["Avaliar", "Coaching"], step_color="#B3B3FF")),
], "#9999FF", "#E0E0FF", "Workforce Engagement Management") + SEP

# 8. Analytics
y += draw_band(X0, y, MAIN_W, [
    C(28, G("Real-time Analytics", 3, [
        "Summary", "Voz", "Representantes", "Bot", "Conversas em\nAndamento", "Backlog",
        "Grupos de Intenção", "Diagnóstico de\nSaúde", "Proativo"])),
    C(30, G("Historical Analytics", 3, [
        "Summary", "Conversa", "Fila", "Voz", "Representante", "Bot", "Correio de Voz",
        "Proactive Outbound", "Bot-Intent / QA Agent"])),
    C(22, G("Supervisão", 2, [
        "Monitorar Conversas", "Atribuir / Transferir\n/ Encerrar", "Monitorar Chamadas\nde Voz",
        "Sentimento em\nTempo Real", "Wallboard View", "Monitorar Filas e\nSelf-service"])),
    C(20, G("Insights &amp; Previsão", 2, [
        "Knowledge Analytics", "Copilot Analytics", "Agent Insights\ne Metas de KPI", "Forecast de Volume",
        "Modelos de Dados\nCustomizáveis", "Filtros, Bookmarks\ne Visuais"])),
], "#FFCC99", "#FFEEDB", "Analytics &amp; Insights") + SEP

# 9. Copilot Service admin center
y += draw_band(X0, y, MAIN_W, [
    C(26, G("Suporte ao Cliente", 3, ["Canais", "Workstreams", "Filas", "Roteamento", "Skills", "Disposition Codes"])),
    C(26, G("Operations", 3, ["Horário de\nFuncionamento", "Perfis de Capacidade", "Mensagens\nAutomáticas",
                              "Templates de\nMensagem", "Fechamento\nAutomático", "Forecasting"])),
    C(28, G("Agent Experience", 3, ["Perfis de Experiência", "Templates de Sessão\ne de Aba", "Templates de\nNotificação",
                                    "Productivity Tools\n(scripts, macros)", "Configurar Inbox", "Configurar Timeline"])),
    C(20, G("Usuários &amp; Personas", 2, ["Gestão de Usuários", "Personas", "Security Roles\nCustomizadas",
                                            "Capacidade e Skills\ndo Usuário"])),
], "#666666", "#F5F5F5", "Copilot Service admin center") + SEP

# 10. Plataforma
y += draw_band(X0, y, MAIN_W, [
    C(18, G("Security &amp; Compliance", 2, ["Mascaramento\nde Dados", "Perfis de\nPagamento", "Configurações de\nAutenticação",
                                              "Exclusão de\nGravações", "Retenção de\nDados", "Responsible AI"])),
    C(16, G("Integrações &amp; Embedded", 2, ["Salesforce", "ServiceNow", "Zendesk", "Qualquer CRM\n(connector)",
                                               "Cobrowse / Tela\n(terceiros)", "Microsoft 365\nCopilot"])),
    C(22, G("APIs &amp; Extensibilidade", 3, ["Messaging APIs", "Direct Line", "Live Chat SDK", "Presence APIs",
                                               "Availability APIs", "Proactive APIs", "Webhooks", "Download de\nGravações",
                                               "Métricas e\nEntidades"])),
    C(14, G("Telefonia &amp; Infra", 1, ["Regiões Suportadas", "Idiomas e Locales", "Billing por Consumo\n(agentes de IA)"])),
    C(16, G("ALM &amp; Migração", 1, ["Solutions\n(configuração)", "Migração de Canais", "Migração ACS →\nTeams Phone"])),
    C(14, G("Configuração de Ambiente", 1, ["Dataverse", "Power Platform\nAdmin Center", "Dev / Test / Prod"])),
], "#666666", "#999999", "Platform", group_stroke="#000000") + SEP

total_h = y - Y0 - SEP

# Coluna direita: Copilot Service workspace / Teams / Modos de implantação
right_groups = [
    G("Copilot Service Workspace", 1, [
        "Sessões e Abas\nmúltiplas", "Painel de Comunicação\n(voz / chat)", "Inbox", "Dashboard do\nRepresentante",
        "Notificações e\nNotificações Perdidas", "Presença", "Painel de Produtividade", "Smart Assist",
        "Scripts de Atendimento\n(agent scripts)", "Macros", "Respostas Rápidas\n(inclusive pessoais)",
        "Mensagens Ricas\ne Formatadas", "Tradução em Tempo Real", "Sentimento em\nTempo Real",
        "Formulários de Conversa\ne Sessão", "Diagnóstico do\nRepresentante",
        "Controles de Chamada\n(espera, mudo, teclado)", "Discador de Saída", "Correio de Voz\ndo Representante",
        "Transcrição e Gravação\nda Chamada", "Calendário do\nRepresentante", "Microsoft 365 Copilot",
        "Estados da Conversa"]),
    G("Microsoft Teams collaboration", 1, [
        "Teams Chat", "Contatos Sugeridos\npor IA / Regras", "Teams Meetings", "Join a Teams Call",
        "Customer Support\nSwarming", "Consulta de Voz\ncom usuários Teams", "Teams Phone\n(telefonia)",
        "Encaminhar chamadas\ndo Teams", "Canal de Mensagens\nMicrosoft Teams"]),
    G("Modos de Implantação", 1, [
        "Contact Center\nStandalone", "Embedded em\nCustomer Service", "Embedded em\nSalesforce",
        "Embedded em\nServiceNow", "Connector p/\nqualquer CRM"]),
]
hs = [group_height(g) for g in right_groups]
extra = (total_h - 2 * PAD - sum(hs) - (len(hs) - 1) * PAD) / len(hs)
cell(L_FEAT, S_BAND % ("#66B2FF", "#CCE5FF"), RX, Y0, RIGHT_W, total_h, "", "band")
cell(L_OVER, S_OVERLAY, RX, Y0, RIGHT_W, total_h, "Representative Experience", "ovl")
gy = Y0 + PAD
for g, h in zip(right_groups, hs):
    draw_group(g, RX + PAD, gy, RIGHT_W - 2 * PAD, h + extra)
    gy += h + extra + PAD

# Título, rodapé e legenda
cell(L_TITLE, "shape=image;imageAspect=0;aspect=fixed;verticalLabelPosition=bottom;verticalAlign=top;align=center;image=%s;" % LOGO,
     X0 + 60, 90, 50, 50, "", "logo")
cell(L_TITLE, "text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=28;fontStyle=0;fontFamily=Segoe UI;",
     X0 + 125, 90, 1000, 50, '<font color="#647687" style="font-size: 28px;">%s</font>'
     % I18N.get("@title", "Dynamics 365 Contact Center - Diagrama Conceitual"), "ttl")
footer_y = Y0 + total_h + 8
cell(L_DET2, "text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=11;fontFamily=Segoe UI;fontColor=#647687;",
     X0, footer_y, 1200, 30,
     I18N.get("@source", "Fonte: documentação oficial Microsoft Learn — Dynamics 365 Contact Center (sincronizada em 20/10/2026). "
              "Itens marcados (preview) podem mudar antes da disponibilidade geral."), "src")
cell(L_DET2, "text;html=1;strokeColor=none;fillColor=none;align=right;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=12;fontFamily=Segoe UI;",
     RX + RIGHT_W - 312, footer_y, 312, 30, "Last update: Oct 2026", "upd")

page_w = int(RX + RIGHT_W + 60)
page_h = int(footer_y + 80)
xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<mxfile host="Electron" version="27.0.9">\n'
       '  <diagram id="mdcc-conceitual-%s" name="%s">\n' % (LANG, escape(I18N.get("@diagram", "00- Diagrama Conceitual MDCC"))) +
       '    <mxGraphModel dx="1600" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
       'pageWidth="%d" pageHeight="%d" background="#E6E6E6" math="0" shadow="1">\n      <root>\n'
       '        <mxCell id="0" />\n'
       '        <mxCell id="%s" value="Features" parent="0" />\n'
       '        <mxCell id="%s" value="Details" parent="0" />\n'
       '        <mxCell id="%s" value="Details 2" parent="0" />\n'
       '        <mxCell id="%s" value="Overlay" parent="0" visible="0" />\n'
       '        <mxCell id="%s" value="Title" parent="0" />\n'
       % (page_w, page_h, L_FEAT, L_DET, L_DET2, L_OVER, L_TITLE))
# Overlay: retângulo escuro + rótulos (como no template)
overlay = ['<mxCell id="mdcc-ovl-bg" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#000000;strokeColor=none;opacity=80;" parent="%s" vertex="1">'
           '<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry" /></mxCell>' % (L_OVER, X0 - 10, Y0 - 10, MAIN_W + SEP + RIGHT_W + 20, total_h + 20)]
ovl = [c for c in cells if 'parent="%s"' % L_OVER in c]
rest = [c for c in cells if 'parent="%s"' % L_OVER not in c]
xml += "\n".join("        " + c for c in rest + overlay + ovl)
xml += "\n      </root>\n    </mxGraphModel>\n  </diagram>\n</mxfile>\n"
open(OUT, "w", encoding="utf-8").write(xml)
print("ok", OUT, "cells=%d" % len(cells), "page=%dx%d" % (page_w, page_h))
