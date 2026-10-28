const { test, expect } = require('@playwright/test');

test.describe('MDCC customer environment - read-only smoke', () => {
  test.skip(!process.env.MDCC_BASE_URL, 'Set MDCC_BASE_URL at runtime.');

  test('opens the approved environment without a server error', async ({ page, baseURL }) => {
    const approvedOrigin = new URL(baseURL).origin;

    page.on('request', request => {
      if (request.isNavigationRequest() && request.frame() === page.mainFrame()) {
        const destination = new URL(request.url());
        if (destination.origin !== approvedOrigin) {
          throw new Error(`Top-level navigation outside the approved origin: ${destination.origin}`);
        }
      }
    });

    const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
    expect(response, 'The initial navigation did not return a response.').not.toBeNull();
    expect(response.status(), 'The environment returned a server error.').toBeLessThan(500);
    await expect(page).toHaveURL(new RegExp(`^${escapeRegExp(approvedOrigin)}`));
  });
});

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
