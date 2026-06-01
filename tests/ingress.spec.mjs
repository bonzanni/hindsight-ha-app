import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:8100/hassio-ingress-test/';

test('control-plane loads under an ingress prefix with no broken assets', async ({ page }) => {
  const failures = [];
  page.on('requestfailed', (r) => failures.push(r.url()));
  page.on('response', (r) => { if (r.status() >= 400) failures.push(`${r.status()} ${r.url()}`); });

  await page.goto(BASE, { waitUntil: 'networkidle' });

  // The app shell rendered (not an nginx error page).
  await expect(page.locator('body')).not.toContainText('502 Bad Gateway');
  // Every asset/data request resolved under the ingress prefix.
  expect(failures, `broken requests:\n${failures.join('\n')}`).toEqual([]);
});
