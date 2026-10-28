import assert from 'node:assert/strict';
import { test } from 'node:test';
import { callTool, createAdoClient, createHandler, htmlToText, loadCredentials, normalizeOrgUrl, resolveFields, segment, textToHtml, TOOLS } from '../tools/ado-mcp/server.mjs';

const credentials = { orgUrl: 'https://dev.azure.com/contoso', auth: { kind: 'pat', token: 'segredo' } };

// fetch falso: `routes` mapeia "MÉTODO /caminho" para o corpo da resposta (ou função).
function fakeFetch(routes, status = 200) {
  const calls = [];
  const impl = async (url, init) => {
    const u = new URL(url);
    calls.push({ url: u, init, body: init.body ? JSON.parse(init.body) : undefined });
    const route = routes[`${init.method} ${u.pathname}`] ?? routes['*'];
    const payload = typeof route === 'function' ? route(calls.length, calls.at(-1)) : route;
    return { ok: status >= 200 && status < 300, status, text: async () => (payload === undefined ? '' : JSON.stringify(payload)) };
  };
  return { impl, calls };
}

const workItem = (rev, extra = {}) => ({
  id: 42,
  rev,
  fields: {
    'System.TeamProject': 'Contact Center',
    'System.WorkItemType': 'User Story',
    'System.Title': 'Roteamento por skill',
    'System.State': 'New',
    'Microsoft.VSTS.Scheduling.StoryPoints': 3,
    'System.Description': '<div>Como <b>supervisor</b><br>quero filas</div>',
    'Microsoft.VSTS.Common.AcceptanceCriteria': '<ul><li>fila X</li><li>fila Y</li></ul>',
    'Custom.Modulo': 'Voz',
    ...extra,
  },
  relations: [{ rel: 'System.LinkTypes.Hierarchy-Reverse', url: 'https://dev.azure.com/contoso/_apis/wit/workItems/7' }],
});

test('ferramentas de leitura e escrita são anotadas corretamente', () => {
  const writes = TOOLS.filter((t) => !t.annotations.readOnlyHint).map((t) => t.name).sort();
  assert.deepEqual(writes, ['ado_add_comment', 'ado_transition_work_item', 'ado_update_work_item']);
  for (const t of TOOLS) assert.equal(t.annotations.destructiveHint, false);
});

test('URL da organização aceita Services e Server e rejeita formatos inseguros', () => {
  assert.equal(normalizeOrgUrl('https://dev.azure.com/contoso/'), 'https://dev.azure.com/contoso');
  assert.equal(normalizeOrgUrl('https://contoso.visualstudio.com'), 'https://contoso.visualstudio.com');
  assert.equal(normalizeOrgUrl('https://ado.contoso.local/tfs/DefaultCollection'), 'https://ado.contoso.local/tfs/DefaultCollection');
  for (const bad of ['http://dev.azure.com/contoso', 'https://dev.azure.com', 'https://dev.azure.com/contoso/Projeto', 'https://u:p@dev.azure.com/contoso', 'https://dev.azure.com/contoso?x=1', 'https://contoso.visualstudio.com/Projeto']) {
    assert.throws(() => normalizeOrgUrl(bad), undefined, bad);
  }
});

test('credenciais: PAT tem prioridade; sem PAT usa Entra ID do Azure CLI com cache', () => {
  const env = { ADO_ORG_URL: 'https://dev.azure.com/contoso', LOCALAPPDATA: '/nao-existe' };
  assert.equal(loadCredentials({ ...env, ADO_PAT: 'x' }).auth.kind, 'pat');
  let calls = 0;
  const entra = loadCredentials(env, { cliToken: () => { calls += 1; return 'tok'; } });
  assert.equal(entra.auth.kind, 'entra');
  assert.equal(entra.auth.token(), 'tok');
  entra.auth.token();
  assert.equal(calls, 1);
  const broken = loadCredentials(env, { cliToken: () => { throw new Error('az ausente'); } });
  assert.throws(() => broken.auth.token(), /az login/);
  assert.throws(() => loadCredentials({ LOCALAPPDATA: '/nao-existe' }), /ADO_ORG_URL/);
});

test('cliente restringe métodos e caminhos; WIQL é o único POST de leitura', async () => {
  const { impl, calls } = fakeFetch({ '*': {} });
  const client = createAdoClient(credentials, impl);
  await client.get('_apis/projects');
  assert.match(calls[0].init.headers.Authorization, /^Basic /);
  assert.equal(calls[0].url.searchParams.get('api-version'), '7.1');
  await assert.rejects(client.get('../x/_apis/projects'), /não permitido/);
  await assert.rejects(client.get('a/b/c/_apis/projects'), /não permitido/);
  await assert.rejects(client.get('_admin/x'), /não permitido/);
  await assert.rejects(client.send('DELETE', '_apis/wit/workitems/1'), /escrita não permitida/);
  await assert.rejects(client.send('POST', 'P/_apis/wit/workitems/$Task'), /escrita não permitida/);
  await assert.rejects(client.send('PATCH', '_apis/projects/1'), /escrita não permitida/);
  await client.send('POST', 'P/_apis/wit/wiql', { query: 'SELECT' });
  await client.send('PATCH', '_apis/wit/workitems/1', []);
  await client.send('POST', 'P/_apis/wit/workItems/1/comments', { text: 'x' });
});

test('Entra ID envia Bearer e resposta HTML de login vira erro de autenticação', async () => {
  const client = createAdoClient({ orgUrl: credentials.orgUrl, auth: { kind: 'entra', token: () => 'jwt' } }, async (url, init) => {
    assert.equal(init.headers.Authorization, 'Bearer jwt');
    return { ok: true, status: 203, text: async () => '<html>Sign in</html>' };
  });
  await assert.rejects(callTool(client, 'ado_whoami'), /recusou a autenticação/);
});

test('segmentos de projeto são codificados e validados', () => {
  assert.equal(segment('Contact Center'), 'Contact%20Center');
  assert.throws(() => segment('a/b'));
  assert.throws(() => segment('..'));
  assert.throws(() => segment(''));
});

test('ado_query_wiql resume work items com HTML convertido e campos Custom', async () => {
  const { impl, calls } = fakeFetch({
    'POST /contoso/Contact%20Center/_apis/wit/wiql': { workItems: [{ id: 42 }] },
    'GET /contoso/Contact%20Center/_apis/wit/workitems': { value: [workItem(5)] },
  });
  const r = await callTool(createAdoClient(credentials, impl), 'ado_query_wiql', { project: 'Contact Center', wiql: "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project" });
  assert.equal(calls[0].url.searchParams.get('$top'), '50');
  assert.equal(calls[1].url.searchParams.get('ids'), '42');
  const wi = r.workItems[0];
  assert.equal(wi.description, 'Como supervisor\nquero filas');
  assert.equal(wi.acceptanceCriteria, '- fila X\n- fila Y');
  assert.equal(wi.storyPoints, '3');
  assert.equal(wi.customFields['Custom.Modulo'], 'Voz');
  assert.deepEqual(wi.links, ['Pai: 7']);
  await assert.rejects(callTool(createAdoClient(credentials, impl), 'ado_query_wiql', { project: 'P', wiql: 'DELETE x' }), /SELECT/);
});

const fieldDefs = [
  { referenceName: 'System.Title', name: 'Title', type: 'string' },
  { referenceName: 'System.State', name: 'State', type: 'string' },
  { referenceName: 'System.Tags', name: 'Tags', type: 'plainText' },
  { referenceName: 'System.CreatedDate', name: 'Created Date', type: 'dateTime', readOnly: true },
  { referenceName: 'Microsoft.VSTS.Scheduling.StoryPoints', name: 'Story Points', type: 'double' },
  { referenceName: 'Microsoft.VSTS.Common.AcceptanceCriteria', name: 'Acceptance Criteria', type: 'html' },
];

test('resolveFields converte por tipo e bloqueia estado e somente leitura', () => {
  const r = resolveFields(fieldDefs, { 'story points': '8', Tags: ['mdcc', 'voz'], 'Acceptance Criteria': '- A\n- B' });
  assert.equal(r['Microsoft.VSTS.Scheduling.StoryPoints'].value, 8);
  assert.equal(r['System.Tags'].value, 'mdcc; voz');
  assert.equal(r['Microsoft.VSTS.Common.AcceptanceCriteria'].value, '<ul><li>A</li><li>B</li></ul>');
  assert.throws(() => resolveFields(fieldDefs, { State: 'Done' }), /ado_transition_work_item/);
  assert.throws(() => resolveFields(fieldDefs, { 'Created Date': 'x' }), /somente leitura/);
  assert.throws(() => resolveFields(fieldDefs, { Inexistente: 1 }), /não existe/);
  assert.throws(() => resolveFields(fieldDefs, { 'Story Points': 'abc' }), /numérico/);
});

test('ado_update_work_item envia JSON Patch com teste de revisão, devolve antes/depois e audita', async () => {
  const { impl, calls } = fakeFetch({
    'GET /contoso/_apis/wit/fields': { value: fieldDefs },
    'GET /contoso/_apis/wit/workitems/42': workItem(5),
    'PATCH /contoso/_apis/wit/workitems/42': workItem(6, { 'Microsoft.VSTS.Scheduling.StoryPoints': 5 }),
  });
  const audits = [];
  const r = await callTool(createAdoClient(credentials, impl), 'ado_update_work_item', { id: 42, fields: { 'Story Points': 5 } }, { audit: (e) => audits.push(e) });
  const patch = calls.find((c) => c.init.method === 'PATCH');
  assert.equal(patch.init.headers['Content-Type'], 'application/json-patch+json');
  assert.deepEqual(patch.body, [{ op: 'test', path: '/rev', value: 5 }, { op: 'add', path: '/fields/Microsoft.VSTS.Scheduling.StoryPoints', value: 5 }]);
  assert.deepEqual(r.updated[0], { field: 'Story Points (Microsoft.VSTS.Scheduling.StoryPoints)', before: '3', after: '5' });
  assert.deepEqual(audits, [{ tool: 'ado_update_work_item', id: 42, fields: ['Microsoft.VSTS.Scheduling.StoryPoints'] }]);
});

test('ado_transition_work_item valida o estado pelo tipo do item', async () => {
  const { impl, calls } = fakeFetch({
    'GET /contoso/_apis/wit/workitems/42': workItem(5),
    'GET /contoso/Contact%20Center/_apis/wit/workitemtypes/User%20Story/states': { value: [{ name: 'New' }, { name: 'Active' }, { name: 'Closed' }] },
    'PATCH /contoso/_apis/wit/workitems/42': workItem(6, { 'System.State': 'Active' }),
  });
  const client = createAdoClient(credentials, impl);
  assert.deepEqual(await callTool(client, 'ado_transition_work_item', { id: 42, state: 'active' }), { id: 42, from: 'New', to: 'Active' });
  assert.deepEqual(calls.at(-1).body.at(-1), { op: 'add', path: '/fields/System.State', value: 'Active' });
  await assert.rejects(callTool(client, 'ado_transition_work_item', { id: 42, state: 'Resolved' }), /indisponível.*Active/);
});

test('ado_add_comment envia HTML escapado na API de comentários', async () => {
  const { impl, calls } = fakeFetch({
    'GET /contoso/_apis/wit/workitems/42': workItem(5),
    'POST /contoso/Contact%20Center/_apis/wit/workItems/42/comments': { id: 9, createdDate: '2026-10-28' },
  });
  const r = await callTool(createAdoClient(credentials, impl), 'ado_add_comment', { id: 42, body: 'Estimativa <5>\n\n- premissa A' });
  assert.equal(r.commentId, 9);
  const post = calls.at(-1);
  assert.equal(post.url.searchParams.get('api-version'), '7.1-preview.4');
  assert.equal(post.body.text, '<p>Estimativa &lt;5&gt;</p><ul><li>premissa A</li></ul>');
});

test('erros HTTP não vazam o PAT', async () => {
  const { impl } = fakeFetch({ '*': { message: 'TF400813: not authorized' } }, 401);
  await assert.rejects(callTool(createAdoClient(credentials, impl), 'ado_whoami'), (e) => /401/.test(e.message) && !e.message.includes('segredo'));
});

test('handler MCP responde initialize, tools/list e erros de ferramenta', async () => {
  const handle = createHandler({ loadClient: () => { throw new Error('Conexão Azure DevOps não configurada'); } });
  const init = await handle({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } });
  assert.equal(init.result.serverInfo.name, 'ado-mdcc');
  const list = await handle({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  assert.ok(list.result.tools.some((t) => t.name === 'ado_query_wiql'));
  const call = await handle({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'ado_whoami' } });
  assert.equal(call.result.isError, true);
});

test('htmlToText e textToHtml preservam parágrafos e listas', () => {
  assert.equal(htmlToText(textToHtml('a\nb\n\n- x\n- y')), 'a\nb\n- x\n- y');
  assert.equal(htmlToText('A &amp; B &#233;'), 'A & B é');
});
