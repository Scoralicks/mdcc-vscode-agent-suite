import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { validateCatalog, applyPreset, checkRuntime, workspaceRoot, catalogPath, runtimePath, templatePath } from '../tools/mcp-configurator/presets.mjs';

const catalog = () => ({ schemaVersion: 1, activeEnvironment: 'dev', environments: [
  { id: 'dev', label: 'Dev', environmentUrl: 'https://contoso.crm4.dynamics.com', classification: 'development' },
  { id: 'test', label: 'Test', environmentUrl: 'https://contoso.crm.dynamics.com/api/mcp', classification: 'unconfirmed' }
] });

test('catálogo normaliza endpoints e rejeita campos extras, duplicatas e seleção inexistente', () => {
  assert.equal(validateCatalog(catalog()).environments[0].endpoint, 'https://contoso.crm4.dynamics.com/api/mcp');
  for (const mutate of [
    c => { c.password = 'not-a-real-credential'; },
    c => { c.environments[0].headers = {}; },
    c => { c.activeEnvironment = 'missing'; },
    c => { c.environments[1].id = 'dev'; },
    c => { c.environments[1].environmentUrl = c.environments[0].environmentUrl; },
    c => { c.environments[0].environmentUrl = 'https://contoso.crm.dynamics.com/api/mcp_preview'; },
    c => { c.environments[0].label = '<script>'; },
    c => { c.environments[0].classification = 'unknown'; }
  ]) {
    const value = catalog(); mutate(value);
    assert.throws(() => validateCatalog(value));
  }
});

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'mdcc-presets-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'config'));
  await mkdir(join(root, '.vscode'));
  await copyFile(join(workspaceRoot, templatePath), join(root, templatePath));
  await copyFile(join(workspaceRoot, 'config/dataverse-mcp-policy.json'), join(root, 'config/dataverse-mcp-policy.json'));
  await copyFile(join(workspaceRoot, templatePath), join(root, runtimePath));
  await writeFile(join(root, catalogPath), JSON.stringify(catalog()));
  execFileSync('git', ['init', '--quiet', root]);
  return root;
}

test('aplica ambiente, preserva Playwright, troca destino e restaura input', async t => {
  const root = await fixture(t);
  const template = JSON.parse(await readFile(join(root, templatePath), 'utf8'));
  await applyPreset(root);
  assert.equal(await checkRuntime(root), 'dev');
  const runtime = JSON.parse(await readFile(join(root, runtimePath), 'utf8'));
  assert.deepEqual(runtime.servers['playwright-mdcc'], template.servers['playwright-mdcc']);
  assert.equal(runtime.inputs.some(input => input.id === 'dataverse-mcp-endpoint'), false);
  const next = catalog(); next.activeEnvironment = 'test';
  await writeFile(join(root, catalogPath), JSON.stringify(next));
  await assert.rejects(checkRuntime(root), /divergente/);
  await applyPreset(root);
  assert.equal(await checkRuntime(root), 'test');
  await applyPreset(root, { reset: true });
  assert.equal(await checkRuntime(root), 'runtime-input');
});

test('erros não alteram conexão anterior nem expõem conteúdo JSON inválido', async t => {
  const root = await fixture(t);
  await applyPreset(root);
  const before = await readFile(join(root, runtimePath), 'utf8');
  await writeFile(join(root, catalogPath), '{private-canary-malformed');
  await assert.rejects(applyPreset(root), error => !error.message.includes('private-canary') && /JSON inválido/.test(error.message));
  assert.equal(await readFile(join(root, runtimePath), 'utf8'), before);
});

test('restrição da política bloqueia aplicação e validação de preset anterior', async t => {
  const root = await fixture(t);
  await applyPreset(root);
  const policyPath = join(root, 'config/dataverse-mcp-policy.json');
  const policy = JSON.parse((await readFile(policyPath, 'utf8')).replace(/^\uFEFF/, ''));
  policy.connection.allowedHostPatterns = ['^contoso\\.crm9\\.dynamics\\.com$'];
  await writeFile(policyPath, JSON.stringify(policy));
  await assert.rejects(applyPreset(root), /política/);
  await assert.rejects(checkRuntime(root), /política/);
});

test('template aceita servidores de work tracking somente com a definição aprovada', async t => {
  const root = await fixture(t);
  const template = JSON.parse(await readFile(join(root, templatePath), 'utf8'));
  for (const name of ['jira-mdcc', 'ado-mdcc']) assert.ok(template.servers[name], `${name} deve estar no template`);
  await applyPreset(root);
  for (const mutate of [
    value => { value.servers['ado-mdcc'].args.push('--extra'); },
    value => { value.servers['jira-mdcc'] = { type: 'http', url: 'https://example.com' }; },
    value => { value.servers['work-mdcc'] = { type: 'stdio', command: 'node', args: [] }; },
    value => { delete value.servers['playwright-mdcc']; },
  ]) {
    const value = structuredClone(template); mutate(value);
    await writeFile(join(root, templatePath), JSON.stringify(value));
    await assert.rejects(applyPreset(root));
  }
});

test('recusa URL local em arquivo rastreado e detecta servidor injetado', async t => {
  const root = await fixture(t);
  execFileSync('git', ['-C', root, 'add', runtimePath]);
  await assert.rejects(applyPreset(root), /rastreada/);
  const runtime = JSON.parse(await readFile(join(root, runtimePath), 'utf8'));
  runtime.servers.extra = { type: 'http', url: 'https://example.com' };
  await writeFile(join(root, runtimePath), JSON.stringify(runtime));
  await assert.rejects(checkRuntime(root), /divergente/);
});
