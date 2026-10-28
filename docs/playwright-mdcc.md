# Playwright para diagnóstico e validação MDCC

O pacote integra `@playwright/test` para testes repetíveis e `@playwright/mcp` para investigação interativa pelo agente **MDCC Browser Diagnostician**. Dependências, configuração e lockfile são versionados; `node_modules` e binários do navegador são instalados localmente e não entram no ZIP.

## Instalação

1. Instale uma versão de Node.js aceita por `package.json`.
2. Execute a task **MDCC: Install Playwright dependencies**. Ela usa `npm ci` e instala somente Chromium.
3. Execute **MDCC: Validate Playwright guardrails**.

## Sessão interativa segura

1. Use UAT/sandbox e uma conta Entra dedicada de menor privilégio.
2. Execute no terminal:

   ```powershell
   pwsh -NoProfile -File .\scripts\prepare-playwright-session.ps1 -EnvironmentUrl https://origem-aprovada.example
   ```

3. Inicie o servidor MCP `playwright-mdcc`. Quando solicitado, informe a mesma origem HTTPS sem caminho, query string ou fragmento.
4. Selecione **MDCC Browser Diagnostician** e descreva o sintoma sem incluir credenciais.
5. Faça SSO/MFA somente na janela isolada. Feche o browser e pare o servidor ao terminar ou trocar de cliente.

O MCP usa contexto em memória, bloqueia download, mantém TLS e sandbox, omite imagens e não salva a sessão. A allowlist reduz navegação acidental, mas não é fronteira de segurança; permissões do cliente MCP, identidade de menor privilégio e supervisão humana continuam obrigatórias.

## Teste funcional versionado

Defina `MDCC_BASE_URL` apenas no processo atual e execute o smoke somente leitura:

```powershell
$env:MDCC_BASE_URL = 'https://origem-aprovada.example'
npm run playwright:test
Remove-Item Env:MDCC_BASE_URL
```

O template não automatiza credenciais. Caso um cenário precise de estado autenticado, grave-o apenas em `playwright/.auth/customer.json`, mantenha-o fora do Git e apague-o ao final. O arquivo pode permitir personificação da conta.

## Limites

- UI E2E não substitui documentação oficial, telemetria, logs nem validação de telefonia/backend.
- Produção e ações que salvam, enviam, publicam, ativam, atribuem ou excluem ficam fora do perfil padrão.
- Traces, screenshots, vídeos e HAR estão desabilitados por padrão porque podem conter PII, tokens e dados do cliente.
- Proxy e certificados corporativos devem ser configurados sem desativar a validação TLS.

Referências oficiais: [instalação](https://playwright.dev/docs/intro), [autenticação](https://playwright.dev/docs/auth), [projetos de teste](https://playwright.dev/docs/test-projects), [Trace Viewer](https://playwright.dev/docs/trace-viewer) e [Playwright MCP](https://github.com/microsoft/playwright-mcp).
