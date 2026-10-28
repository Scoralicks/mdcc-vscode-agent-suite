const { defineConfig, devices } = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');

const baseURL = process.env.MDCC_BASE_URL;
if (baseURL) {
  const parsed = new URL(baseURL);
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
    throw new Error('MDCC_BASE_URL must be an HTTPS URL without embedded credentials.');
  }
}

const authFile = path.join(__dirname, 'playwright', '.auth', 'customer.json');

module.exports = defineConfig({
  testDir: './tests/e2e',
  outputDir: './test-results',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list'], ['html', { outputFolder: 'playwright-report', open: 'never' }]],
  use: {
    baseURL,
    ...devices['Desktop Chrome'],
    storageState: fs.existsSync(authFile) ? authFile : undefined,
    trace: 'off',
    screenshot: 'off',
    video: 'off',
    ignoreHTTPSErrors: false,
    acceptDownloads: false
  },
  projects: [{ name: 'mdcc-chromium', use: { browserName: 'chromium' } }]
});
