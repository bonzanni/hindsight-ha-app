import { defineConfig, devices } from '@playwright/test';

// The add-on stack (add-on container + ingress-mimic) is booted out-of-band by
// the operator / CI before running these tests — see tests/README or the
// commands in the Task 9 section of the implementation plan. No webServer here.
export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.mjs',
  fullyParallel: false,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:8100/hassio-ingress-test/',
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
