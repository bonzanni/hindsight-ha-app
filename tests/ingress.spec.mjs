import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:8100/hassio-ingress-test/';
const ORIGIN = new URL(BASE).origin;
const PREFIX = new URL(BASE).pathname; // /hassio-ingress-test/

// Collect responses that are either errors (>=400) or that escaped the ingress
// prefix (a request to the origin root, i.e. NOT under PREFIX). An escaped
// request is the signature of a basePath/rewrite gap — it bypasses the add-on
// and 404s on the real HA frontend.
function trackBroken(page) {
  const bad = [];
  page.on('requestfailed', (r) => {
    const u = r.url();
    const headers = r.headers();
    const isOrigin = u.startsWith(ORIGIN);
    const path = isOrigin ? u.slice(ORIGIN.length) : u;
    const escaped = isOrigin && !path.startsWith(PREFIX);
    // Next.js speculatively prefetches every visible App Router link and may
    // cancel unused RSC prefetches. Chromium reports those intentional
    // cancellations as requestfailed/net::ERR_ABORTED. Ignore only an
    // explicitly marked, in-prefix RSC prefetch; real navigation/asset
    // failures and escaped prefetches remain release blockers.
    const expectedPrefetchAbort =
      r.failure()?.errorText === 'net::ERR_ABORTED' &&
      headers['next-router-prefetch'] === '1' &&
      headers.rsc === '1' &&
      isOrigin &&
      !escaped;
    if (expectedPrefetchAbort) return;
    bad.push(
      `FAILED ${r.failure()?.errorText ?? 'unknown'}` +
      ` prefetch=${headers['next-router-prefetch'] ?? '-'}` +
      ` segment=${headers['next-router-segment-prefetch'] ?? '-'}` +
      ` rsc=${headers.rsc ?? '-'} ${u}`,
    );
  });
  page.on('response', (r) => {
    const u = r.url();
    const isOrigin = u.startsWith(ORIGIN);
    const path = isOrigin ? u.slice(ORIGIN.length) : u;
    const escaped = isOrigin && !path.startsWith(PREFIX);
    if (r.status() >= 400 || escaped) bad.push(`${r.status()}${escaped ? ' [ESCAPED-PREFIX]' : ''} ${path}`);
  });
  return bad;
}

test('control-plane loads under an ingress prefix with no broken assets', async ({ page }) => {
  const bad = trackBroken(page);
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await expect(page.locator('body')).not.toContainText('502 Bad Gateway');
  expect(bad, `broken/escaped requests:\n${bad.join('\n')}`).toEqual([]);
});

// Regression: client-side navigation into a memory bank must stay within the
// ingress prefix. With basePath="" the App Router emitted root-absolute
// /banks/<id> RSC fetches that escaped the prefix and 404'd; the placeholder
// basePath + nginx rewrite fixes it. Requires a "Test" bank to exist (seeded by
// tests/run-ingress.sh).
test('opening a bank navigates within the ingress prefix (no escaped requests)', async ({ page }) => {
  const bad = trackBroken(page);
  await page.goto(BASE, { waitUntil: 'networkidle' });
  // the bank picker is a combobox; open it and choose the seeded "Test" bank
  await page.getByRole('combobox').click();
  await page.getByRole('option', { name: /Test/ }).first().click();
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
  // the browser URL stays under the ingress prefix and reaches the bank route
  await expect(page).toHaveURL(new RegExp(`${PREFIX}.*banks/Test`));
  expect(bad, `broken/escaped requests:\n${bad.join('\n')}`).toEqual([]);
});
