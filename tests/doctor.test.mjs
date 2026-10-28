import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { formatReport, runChecks } from '../tools/doctor/doctor.mjs';
import { workspaceRoot } from '../tools/mcp-configurator/presets.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'mdcc-doctor-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'config'));
  await mkdir(join(root, '.vscode'));
  await mkdir(join(root, '.reference'));
  await copyFile(join(workspaceRoot, 'config/mcp.template.json'), join(root, 'config/mcp.template.json'));
  await copyFile(join(workspaceRoot, 'config/mcp.template.json'), join(root, '.vscode/mcp.json'));
  await copyFile(join(workspaceRoot, 'config/dataverse-mcp-policy.json'), join(root, 'config/dataverse-mcp-policy.json'));
  return root;
}

const byArea = (checks) => Object.fromEntries(checks.map((c) => [c.area, c]));
const now = Date.parse('2026-10-28T00:00:00Z');
const base = { exists: () => true, now, nodeVersion: '24.1.0', readUser: () => undefined };

test('estação vazia: bloqueia só por Node/Git e orienta cada lacuna sem segredos', async (t) => {
  const root = await fixture(t);
  const checks = byArea(await runChecks({ ...base, root, env: { LOCALAPPDATA: root, APPDATA: root }, exists: () => false, nodeVersion: '20.0.0' }));
  assert.equal(checks['Node.js'].status, 'fail');
  assert.equal(checks.Git.status, 'fail');
  assert.equal(checks['Documentação oficial'].status, 'warn');
  assert.equal(checks['Dataverse (ambiente)'].status, 'warn');
  assert.equal(checks['VS Code MCP'].status, 'ok');
  assert.equal(checks.Jira.status, 'info');
  assert.equal(checks['Azure DevOps'].status, 'info');
  assert.match(formatReport(Object.values(checks)), /bloqueante/);
});

test('estação configurada: documentação recente com Customer Service, Dataverse por variável e work tracking', async (t) => {
  const root = await fixture(t);
  await writeFile(join(root, '.reference/mdcc-doc-index.json'), JSON.stringify({
    generatedAtUtc: '2026-10-25T00:00:00Z', count: 2,
    files: [{ path: 'contact-center/a.md' }, { repository: 'dynamics-365-customer-engagement', path: 'ce/customer-service/b.md' }],
  }));
  const env = { LOCALAPPDATA: root, APPDATA: root, MDCC_DATAVERSE_URL: 'https://contoso.crm4.dynamics.com', JIRA_BASE_URL: 'https://contoso.atlassian.net', JIRA_EMAIL: 'a@b.com', JIRA_API_TOKEN: 'segredo-jira', ADO_ORG_URL: 'https://dev.azure.com/contoso', ADO_PAT: 'segredo-ado' };
  const list = await runChecks({ ...base, root, env });
  const checks = byArea(list);
  assert.equal(checks['Documentação oficial'].status, 'ok');
  assert.match(checks['Dataverse (ambiente)'].detail, /contoso\.crm4\.dynamics\.com/);
  assert.equal(checks.Jira.status, 'ok');
  assert.equal(checks['Azure DevOps'].status, 'ok');
  const text = JSON.stringify(list) + formatReport(list);
  assert.ok(!text.includes('segredo'), 'o relatório não pode conter segredos');
});

test('documentação antiga ou sem Customer Service gera aviso; ADO sem credencial gera aviso', async (t) => {
  const root = await fixture(t);
  await writeFile(join(root, '.reference/mdcc-doc-index.json'), JSON.stringify({ generatedAtUtc: '2026-09-01T00:00:00Z', count: 1, files: [{ path: 'contact-center/a.md' }] }));
  const checks = byArea(await runChecks({ ...base, root, env: { LOCALAPPDATA: root, APPDATA: root, ADO_ORG_URL: 'https://dev.azure.com/contoso' }, exists: (name) => name !== 'az' }));
  assert.equal(checks['Documentação oficial'].status, 'warn');
  assert.equal(checks['Azure DevOps'].status, 'warn');
});
