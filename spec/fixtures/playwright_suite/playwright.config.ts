import { defineConfig, devices } from '@playwright/test';
// Suite de ejemplo "Tienda Demo": genera spec/fixtures/playwright_report.json (ver README).
export default defineConfig({
  testDir: './tests',
  retries: 2,
  workers: 4,
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
