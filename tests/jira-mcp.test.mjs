import assert from 'node:assert/strict';
import { test } from 'node:test';
import { adfToText, callTool, createHandler, createJiraClient, normalizeBaseUrl, resolveFields, textToAdf, TOOLS } from '../tools/jira-mcp/server.mjs';

const credentials = { baseUrl: 'https://exemplo.atlassian.net', email: 'a@b.com', token: 'segredo' };

// fetch falso: `routes` mapeia "MÉTODO /caminho" para o corpo da resposta (ou função).
function fakeFetch(routes, status = 200) {
  const calls = [];
  const impl = async (url, init) => {
    const u = new URL(url);
    calls.push({ url: u, init, body: init.body ? JSON.parse(init.body) : undefined });
    const route = routes[`${init.method} ${u.pathname}`] ?? routes['*'];
    const payload = typeof route === 'function' ? route(calls.length) : route;
    return { ok: status < 400, status, text: async () => (payload === undefined ? '' : JSON.stringify(payload)) };
  };
  return { impl, calls };
}

test('ferramentas de leitura e escrita são anotadas corretamente', () => {
  const writes = TOOLS.filter((t) => !t.annotations.readOnlyHint).map((t) => t.name).sort();
  assert.deepEqual(writes, ['jira_add_comment', 'jira_transition_issue', 'jira_update_issue']);
  for (const t of TOOLS) assert.equal(t.annotations.destructiveHint, false);
});

test('cliente restringe métodos e caminhos de escrita', async () => {
  const { impl, calls } = fakeFetch({ '*': {} });
  const client = createJiraClient(credentials, impl);
  await client.get('/rest/api/3/myself');
  assert.equal(calls[0].init.method, 'GET');
  assert.match(calls[0].init.headers.Authorization, /^Basic /);
  await assert.rejects(client.get('/rest/internal/1/x'), /não permitido/);
  await assert.rejects(client.get('/rest/api/3/../../x'), /não permitido/);
  await assert.rejects(client.send('DELETE', '/rest/api/3/issue/ABC-1'), /escrita não permitida/);
  await assert.rejects(client.send('POST', '/rest/api/3/issue'), /escrita não permitida/);
  await assert.rejects(client.send('PUT', '/rest/api/3/project/ABC'), /escrita não permitida/);
  await client.send('PUT', '/rest/api/3/issue/ABC-1', { fields: {} });
  await client.send('POST', '/rest/api/3/issue/ABC-1/comment', { body: {} });
  await client.send('POST', '/rest/api/3/issue/ABC-1/transitions', { transition: { id: '1' } });
});

test('URL base exige origem HTTPS', () => {
  assert.equal(normalizeBaseUrl('https://exemplo.atlassian.net/'), 'https://exemplo.atlassian.net');
  assert.throws(() => normalizeBaseUrl('http://exemplo.atlassian.net'));
  assert.throws(() => normalizeBaseUrl('https://exemplo.atlassian.net/jira'));
});

test('jira_search resume issues com campos personalizados nomeados', async () => {
  const { impl, calls } = fakeFetch({
    'GET /rest/api/3/search/jql': {
      isLast: true,
      names: { customfield_10016: 'Story point estimate', customfield_10050: 'Critérios de aceite' },
      issues: [{
        key: 'ABC-1',
        fields: {
          summary: 'Roteamento por skill', issuetype: { name: 'Story' }, status: { name: 'To Do' },
          description: { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Como agente' }] }] },
          customfield_10016: 5,
          customfield_10050: textToAdf('- fila X'),
          customfield_99999: null,
        },
      }],
    },
  });
  const result = await callTool(createJiraClient(credentials, impl), 'jira_search', { jql: 'project = ABC' });
  assert.equal(calls[0].url.searchParams.get('jql'), 'project = ABC');
  const issue = result.issues[0];
  assert.equal(issue.description, 'Como agente');
  assert.equal(issue.otherFields['Story point estimate (customfield_10016)'], '5');
  assert.equal(issue.otherFields['Critérios de aceite (customfield_10050)'], '- fila X');
  assert.ok(!('customfield_99999' in issue.otherFields));
});

const editmeta = {
  fields: {
    summary: { name: 'Summary', schema: { type: 'string', system: 'summary' } },
    description: { name: 'Description', schema: { type: 'string', system: 'description' } },
    labels: { name: 'Labels', schema: { type: 'array', items: 'string', system: 'labels' } },
    priority: { name: 'Priority', schema: { type: 'priority', system: 'priority' } },
    customfield_10016: { name: 'Story point estimate', schema: { type: 'number', custom: 'com.atlassian.jira.plugin.system.customfieldtypes:float' } },
    customfield_10050: { name: 'Critérios de aceite', schema: { type: 'string', custom: 'com.atlassian.jira.plugin.system.customfieldtypes:textarea' } },
    customfield_10060: { name: 'Complexidade', schema: { type: 'option', custom: 'x:select' } },
    timetracking: { name: 'Time tracking', schema: { type: 'timetracking', system: 'timetracking' } },
  },
};

test('resolveFields converte valores pelo schema e valida nomes', () => {
  const r = resolveFields(editmeta, { 'story point estimate': '8', labels: 'mdcc, voz', 'Critérios de aceite': '- A\n- B', Priority: 'High', Complexidade: 'Alta' });
  assert.equal(r.customfield_10016.value, 8);
  assert.deepEqual(r.labels.value, ['mdcc', 'voz']);
  assert.equal(r.customfield_10050.value.content[0].type, 'bulletList');
  assert.deepEqual(r.priority.value, { name: 'High' });
  assert.deepEqual(r.customfield_10060.value, { value: 'Alta' });
  assert.deepEqual(resolveFields(editmeta, { 'time tracking': '3d 4h' }).timetracking.value, { originalEstimate: '3d 4h' });
  assert.throws(() => resolveFields(editmeta, { Sprint: 1 }), /não é editável/);
  assert.throws(() => resolveFields(editmeta, { 'Story point estimate': 'abc' }), /numérico/);
});

test('jira_update_issue envia PUT, devolve antes/depois e audita', async () => {
  const { impl, calls } = fakeFetch({
    'GET /rest/api/3/issue/ABC-1/editmeta': editmeta,
    'GET /rest/api/3/issue/ABC-1': (n) => ({ fields: { customfield_10016: n <= 2 ? 3 : 5 } }),
    'PUT /rest/api/3/issue/ABC-1': undefined,
  });
  const audits = [];
  const r = await callTool(createJiraClient(credentials, impl), 'jira_update_issue', { issueKey: 'abc-1', fields: { 'Story point estimate': 5 } }, { audit: (e) => audits.push(e) });
  const put = calls.find((c) => c.init.method === 'PUT');
  assert.deepEqual(put.body, { fields: { customfield_10016: 5 } });
  assert.deepEqual(r.updated[0], { field: 'Story point estimate (customfield_10016)', before: '3', after: '5' });
  assert.deepEqual(audits, [{ tool: 'jira_update_issue', issueKey: 'ABC-1', fields: ['customfield_10016'] }]);
});

test('jira_transition_issue exige transição única e válida', async () => {
  const transitions = { transitions: [{ id: '21', name: 'Iniciar', to: { name: 'Em andamento' } }, { id: '31', name: 'Concluir', to: { name: 'Concluído' } }] };
  const { impl, calls } = fakeFetch({
    'GET /rest/api/3/issue/ABC-1/transitions': transitions,
    'GET /rest/api/3/issue/ABC-1': { fields: { status: { name: 'A fazer' } } },
    'POST /rest/api/3/issue/ABC-1/transitions': undefined,
  });
  const client = createJiraClient(credentials, impl);
  const r = await callTool(client, 'jira_transition_issue', { issueKey: 'ABC-1', transition: 'em andamento' });
  assert.deepEqual(r, { issueKey: 'ABC-1', from: 'A fazer', to: 'Em andamento', transition: 'Iniciar' });
  assert.deepEqual(calls.at(-1).body, { transition: { id: '21' } });
  await assert.rejects(callTool(client, 'jira_transition_issue', { issueKey: 'ABC-1', transition: 'Cancelar' }), /indisponível.*Iniciar/);
});

test('jira_add_comment envia ADF', async () => {
  const { impl, calls } = fakeFetch({ 'POST /rest/api/3/issue/ABC-1/comment': { id: '100', created: '2026-10-23' } });
  const r = await callTool(createJiraClient(credentials, impl), 'jira_add_comment', { issueKey: 'ABC-1', body: 'Estimativa: 5 pts\n\n- premissa A' });
  assert.equal(r.commentId, '100');
  assert.deepEqual(calls[0].body.body.content.map((b) => b.type), ['paragraph', 'bulletList']);
});

test('erros HTTP não vazam o token', async () => {
  const { impl } = fakeFetch({ '*': { errorMessages: ['Unauthorized'] } }, 401);
  await assert.rejects(callTool(createJiraClient(credentials, impl), 'jira_whoami'), (e) => /401/.test(e.message) && !e.message.includes('segredo'));
});

test('handler MCP responde initialize, tools/list e erros de ferramenta', async () => {
  const handle = createHandler({ loadClient: () => { throw new Error('Conexão Jira não configurada'); } });
  const init = await handle({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } });
  assert.equal(init.result.serverInfo.name, 'jira-mdcc');
  assert.equal(await handle({ jsonrpc: '2.0', method: 'notifications/initialized' }), undefined);
  const list = await handle({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  assert.ok(list.result.tools.some((t) => t.name === 'jira_update_issue'));
  const call = await handle({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'jira_whoami' } });
  assert.equal(call.result.isError, true);
});

test('adfToText e textToAdf fazem ida e volta', () => {
  assert.equal(adfToText(textToAdf('a\nb')).trim(), 'a\nb');
  assert.equal(adfToText(textToAdf('- x\n- y')).trim(), '- x\n- y');
});
