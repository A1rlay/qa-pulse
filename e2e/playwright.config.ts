import { defineConfig, devices } from '@playwright/test';
// Pruebas E2E de QA Pulse (un recorrido por historia). Requieren el servidor en marcha.
// Ver README: sección "Pruebas end-to-end".
export default defineConfig({
  testDir: './tests',
  retries: 0,
  workers: 1,
  use: { baseURL: process.env.QA_PULSE_URL || 'http://127.0.0.1:3000', locale: 'es-MX', timezoneId: 'America/Ciudad_Juarez' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
