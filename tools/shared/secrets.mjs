// Leitura de segredos locais compartilhada pelos servidores MCP de work tracking.
// Nenhum segredo é gravado aqui; os arquivos são produzidos pelos scripts set-*-connection.ps1.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

export function secretDirectory(env = process.env) {
  const base = env.LOCALAPPDATA ?? join(env.USERPROFILE ?? env.HOME ?? '.', 'AppData', 'Local');
  return join(base, 'mdcc-agent-suite');
}

// Variável de usuário do Windows (HKCU\Environment), útil quando o processo foi
// iniciado antes de setx/SetEnvironmentVariable e não herdou o valor.
export function readUserEnvironment(name) {
  if (process.platform !== 'win32') return undefined;
  try {
    const out = execFileSync('reg', ['query', 'HKCU\\Environment', '/v', name], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const match = out.match(new RegExp(`${name}\\s+REG_(?:EXPAND_)?SZ\\s+(.*)`));
    return match?.[1].trim() || undefined;
  } catch { return undefined; }
}

// Decifra um SecureString exportado por ConvertFrom-SecureString (DPAPI, usuário atual).
export function readProtectedToken(file) {
  if (process.platform !== 'win32' || !existsSync(file)) return undefined;
  // PSCredential funciona no Windows PowerShell 5.1; NetworkCredential::new("", $s) devolve senha vazia nele.
  const script = '$s = (Get-Content -Raw -LiteralPath $env:MDCC_TOKEN_FILE).Trim() | ConvertTo-SecureString; (New-Object System.Management.Automation.PSCredential "mdcc", $s).GetNetworkCredential().Password';
  // pwsh primeiro; no 5.1, o PSModulePath herdado do pwsh impede carregar ConvertTo-SecureString.
  for (const exe of ['pwsh.exe', 'powershell.exe']) {
    const env = { ...process.env, MDCC_TOKEN_FILE: file };
    if (exe === 'powershell.exe') for (const k of Object.keys(env)) if (k.toLowerCase() === 'psmodulepath') delete env[k];
    try {
      const token = execFileSync(exe, ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], env }).trim();
      if (token) return token;
    } catch { /* tenta o próximo */ }
  }
  return undefined;
}
