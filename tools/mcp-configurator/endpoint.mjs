import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

export function loadConnectionPolicy(root = resolve(import.meta.dirname, '../..')) {
  try {
    const policy = JSON.parse(readFileSync(join(root, 'config/dataverse-mcp-policy.json'), 'utf8').replace(/^\uFEFF/, ''));
    if (policy.connection?.requiredScheme !== 'https' || policy.connection?.allowedPath !== '/api/mcp' ||
        policy.connection?.previewAllowed !== false || !Array.isArray(policy.connection?.allowedHostPatterns) ||
        !policy.connection.allowedHostPatterns.length) throw new Error();
    return policy.connection;
  } catch { throw new Error('Política de conexão ausente ou inválida.'); }
}

export function normalizeDataverseEndpoint(input, connection = loadConnectionPolicy()) {
  if (typeof input !== 'string' || !input.trim()) throw new Error('Informe a URL do ambiente.');
  let parsed;
  try { parsed = new URL(input.trim()); } catch { throw new Error('A URL informada não é válida.'); }
  if (parsed.protocol !== 'https:') throw new Error('Use somente HTTPS.');
  if (parsed.port && parsed.port !== '443') throw new Error('Use a porta HTTPS padrão.');
  if (parsed.username || parsed.password) throw new Error('Credenciais na URL são proibidas.');
  if (parsed.search || parsed.hash) throw new Error('Query string e fragmento não são permitidos.');
  if (parsed.hostname.endsWith('.') || parsed.hostname.startsWith('xn--') || parsed.hostname.includes('.xn--')) throw new Error('O nome do host não é permitido.');
  let hostAllowed = false;
  try { hostAllowed = connection.allowedHostPatterns.some(pattern => new RegExp(pattern).test(parsed.hostname)); }
  catch { throw new Error('Política de conexão inválida.'); }
  if (connection.requiredScheme !== 'https' || connection.allowedPath !== '/api/mcp' || connection.previewAllowed !== false || !hostAllowed) {
    throw new Error('Endpoint rejeitado pela política de conexão.');
  }
  const path = parsed.pathname.replace(/\/+$/, '');
  if (path && path !== '/api/mcp') throw new Error('Informe a URL base ou o endpoint terminado em /api/mcp.');
  return `https://${parsed.hostname.toLowerCase()}/api/mcp`;
}
