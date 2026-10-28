import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { spawn } from 'node:child_process';
import { normalizeDataverseEndpoint, loadConnectionPolicy } from './endpoint.mjs';
import { loadCatalog, workspaceRoot } from './presets.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const pagePath = join(scriptDir, 'index.html');
export async function startConfigurator({ open = false, idleTimeoutMs = 10 * 60_000, root = workspaceRoot } = {}) {
  let csrfToken = randomBytes(24).toString('hex');
  let expectedOrigin;
  let shutdownTimer;
  const server = createServer(async (request, response) => {
  try {
    if (!expectedOrigin || request.headers.host !== new URL(expectedOrigin).host) throw userError('Host local inválido.', 403);
    applySecurityHeaders(response);
    const requestUrl = new URL(request.url ?? '/', expectedOrigin);

    if (request.method === 'GET' && requestUrl.pathname === '/') {
      const html = await readFile(pagePath, 'utf8');
      response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      response.end(html.replaceAll('__CSRF_TOKEN__', csrfToken));
      refreshShutdown(idleTimeoutMs);
      return;
    }
    if (request.method === 'POST' && requestUrl.pathname === '/api/presets') {
      requireLocalRequest(request);
      await readJsonBody(request);
      const catalog = await loadCatalog(root);
      return sendJson(response, 200, catalog);
    }
    if (request.method === 'POST' && requestUrl.pathname === '/api/validate') {
      requireLocalRequest(request);
      const body = await readJsonBody(request);
      const endpoint = normalizeDataverseEndpoint(body.environmentUrl, loadConnectionPolicy(root));
      csrfToken = randomBytes(24).toString('hex');
      refreshShutdown(Math.min(idleTimeoutMs, 5 * 60_000));
      return sendJson(response, 200, {
        valid: true,
        endpoint,
        persisted: false,
        csrfToken,
        nextStep: "Para aplicar, atualize environmentUrl no catálogo local e execute a task MDCC: Apply predefined MCP environment. Esta validação não altera a conexão ativa."
      });
    }
    if (request.method === 'POST' && requestUrl.pathname === '/api/close') {
      requireLocalRequest(request);
      sendJson(response, 200, { closing: true });
      setTimeout(() => server.close(), 100);
      return;
    }
    sendJson(response, 404, { error: 'Recurso não encontrado.' });
  } catch (error) {
    sendJson(response, error.statusCode ?? 400, { error: error.message });
  }
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  expectedOrigin = `http://127.0.0.1:${address.port}`;
  refreshShutdown(idleTimeoutMs);
  if (open) openBrowser(`${expectedOrigin}/`);
  function requireLocalRequest(request) {
  if (request.headers.origin !== expectedOrigin) throw userError('Origem local inválida.', 403);
  const provided = Buffer.from(String(request.headers['x-mdcc-csrf'] ?? ''));
  const expected = Buffer.from(csrfToken);
  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) throw userError('Sessão local inválida.', 403);
  }

async function readJsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) throw userError('Requisição excede o tamanho permitido.', 413);
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw userError('Conteúdo JSON inválido.'); }
}

function applySecurityHeaders(response) {
  response.setHeader('cache-control', 'no-store');
  response.setHeader('content-security-policy', "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
  response.setHeader('x-content-type-options', 'nosniff');
  response.setHeader('x-frame-options', 'DENY');
  response.setHeader('referrer-policy', 'no-referrer');
}

function sendJson(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(body));
}

function userError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

  function refreshShutdown(milliseconds) {
  clearTimeout(shutdownTimer);
  shutdownTimer = setTimeout(() => server.close(), milliseconds);
  shutdownTimer.unref();
  }

  return { server, origin: expectedOrigin };
}

function openBrowser(url) {
  const platform = process.platform;
  const command = platform === 'win32' ? 'powershell.exe' : platform === 'darwin' ? 'open' : 'xdg-open';
  const args = platform === 'win32' ? ['-NoProfile', '-Command', 'Start-Process', url] : [url];
  const child = spawn(command, args, { detached: true, stdio: 'ignore', windowsHide: true });
  child.unref();
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  const { server, origin } = await startConfigurator({ open: !process.argv.includes('--no-open') });
  console.log('Configurador MDCC iniciado em loopback. Pressione Ctrl+C para encerrar.');
  console.log(`URL local: ${origin}/`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
