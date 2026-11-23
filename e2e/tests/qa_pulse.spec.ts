import { test, expect, Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

const SLUG = 'tienda-demo';

// Falla la prueba ante cualquier error de consola o violación de la CSP.
function trackConsole(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  page.on('pageerror', (e) => problems.push(e.message));
  return problems;
}

test('el tablero carga por AJAX y muestra una subida nueva sin recargar', async ({ page, request }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}`);

  await expect(page.locator('#trend-chart')).toBeVisible();
  await expect(page.locator('[data-flaky-body] tr')).toHaveCount(3);
  await expect(page.getByText(/En vivo · actualizado/)).toBeVisible();
  await page.screenshot({ path: 'screenshots/dashboard.png', fullPage: true });

  const before = await page.locator('[data-latest-meta] a:not([data-compare-link])').textContent();
  let navigations = 0;
  page.on('framenavigated', () => navigations++);

  // Subida en vivo, como bin/demo_upload.
  const report = JSON.parse(readFileSync('/fixtures/playwright_report.json', 'utf8'));
  report.stats.startTime = new Date().toISOString();
  const res = await request.post(`/api/v1/projects/${SLUG}/runs?branch=e2e`, {
    headers: { Authorization: `Bearer ${process.env.QA_PULSE_TOKEN}` }, data: report,
  });
  expect(res.status()).toBe(201);
  const { id } = await res.json();

  await expect(page.locator('[data-latest-meta] a:not([data-compare-link])')).toHaveText(`#${id}`, { timeout: 15_000 });
  expect(before).not.toBe(`#${id}`);
  expect(navigations).toBe(0); // no hubo recarga
  expect(problems).toEqual([]);
});

test('el detalle de una ejecución filtra por estado y expande el error', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}`);
  await page.locator('[data-latest-meta] a:not([data-compare-link])').click();

  const rows = page.locator('tbody tr[data-status]');
  await expect(rows).toHaveCount(30);
  await page.getByRole('button', { name: /Falló/ }).click();
  await expect(page.locator('tbody tr[data-status]:visible')).toHaveCount(1);
  await expect(page.getByText('Mostrando 1 de 30 pruebas.')).toBeVisible();
  expect(page.url()).toContain('estado=failed');

  await page.getByText('Ver error', { exact: true }).click();
  await expect(page.locator('pre.error:visible')).toContainText('Expected: "$268.20"');
  await page.screenshot({ path: 'screenshots/run.png', fullPage: true });
  expect(problems).toEqual([]);
});

test('el historial de una prueba muestra la tira de estados', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}`);
  await page.getByRole('link', { name: 'Catálogo > Filtros > filtra por rango de precio' }).click();
  await expect(page.locator('.strip li')).toHaveCount(await page.locator('.strip li').count());
  expect(await page.locator('.strip li').count()).toBeGreaterThanOrEqual(15);
  await expect(page.getByText(/Esta prueba es inestable/)).toBeVisible();
  await page.screenshot({ path: 'screenshots/history.png', fullPage: true });
  expect(problems).toEqual([]);
});

test('crear un proyecto muestra el token y el comando curl', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto('/');
  const name = `E2E ${Date.now()}`;
  await page.getByLabel('Nombre').fill(name);
  await page.getByRole('button', { name: 'Crear proyecto' }).click();
  const created = page.locator('.card--highlight');
  await expect(created).toContainText(`«${name}»`);
  await expect(created.locator('code[id^="token-"]')).toHaveText(/^[0-9a-f]{64}$/);
  await expect(created.locator('code[id^="curl-"]')).toContainText('Authorization: Bearer');
  await page.screenshot({ path: 'screenshots/projects.png', fullPage: true });
  expect(problems).toEqual([]);
});

test('los datos del reporte se pintan como texto (sin XSS por AJAX)', async ({ page, request }) => {
  const payload = 'e2e<img src=x onerror="window.__xss=1">';
  const report = JSON.parse(readFileSync('/fixtures/playwright_report.json', 'utf8'));
  report.stats.startTime = new Date().toISOString();
  const res = await request.post(`/api/v1/projects/${SLUG}/runs?branch=${encodeURIComponent(payload)}`, {
    headers: { Authorization: `Bearer ${process.env.QA_PULSE_TOKEN}` }, data: report,
  });
  expect(res.status()).toBe(201);

  await page.goto(`/projects/${SLUG}`);
  await page.getByText('Ver los datos de la gráfica en una tabla').click();
  await expect(page.locator('[data-runs-body]')).toContainText(payload); // visible como texto
  await expect(page.locator('[data-latest-meta]')).toContainText(payload);
  expect(await page.locator('#dashboard img:not(.badge-preview)').count()).toBe(0); // la única imagen legítima es la insignia
  expect(await page.evaluate(() => (window as any).__xss)).toBeUndefined();
});

test('comparar: el enlace "¿qué cambió?" muestra la regresión del cupón', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}/compare`);
  // En los datos de demo la regresión aparece al pasar de la ejecución 12 a la 13.
  const options = page.locator('select[name="head"] option');
  const ids = await options.evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value));
  const chrono = [...ids].reverse(); // las opciones vienen de la más reciente a la más antigua
  await page.selectOption('select[name="base"]', chrono[11]);
  await page.selectOption('select[name="head"]', chrono[12]);
  await page.getByRole('button', { name: 'Comparar' }).click();
  const newFailures = page.locator('section', { has: page.getByRole('heading', { name: /Nuevas fallas/ }) });
  await expect(newFailures).toContainText('Checkout > aplica un cupón de descuento');
  await page.screenshot({ path: 'screenshots/compare.png', fullPage: true });
  expect(problems).toEqual([]);
});

test('insights: búsqueda por AJAX, mapa de calor y filtro de rama', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}/insights`);
  await expect(page.locator('.heatmap tbody tr')).not.toHaveCount(0);
  await expect(page.locator('[data-slow-list] li')).toHaveCount(10);

  await page.getByLabel('Buscar por título o archivo').fill('cupón');
  await expect(page.locator('[data-search-results] li')).toHaveCount(1);
  await expect(page.locator('[data-search-results]')).toContainText('aplica un cupón de descuento');
  await page.getByLabel('Buscar por título o archivo').fill('zzzz');
  await expect(page.getByText('Ninguna prueba coincide con «zzzz».')).toBeVisible();

  // En "main" la regresión del cupón no existe: el mapa de calor no debe mostrarla.
  await page.getByLabel('Rama').selectOption('main');
  await expect(page).toHaveURL(/rama=main/);
  await expect(page.locator('.heatmap tbody')).not.toContainText('aplica un cupón de descuento');
  await page.getByLabel('Rama').selectOption('');
  await expect(page.locator('.heatmap tbody')).toContainText('aplica un cupón de descuento');
  await page.getByLabel('Buscar por título o archivo').fill('carrito');
  await expect(page.locator('[data-search-results] li')).toHaveCount(8); // las 8 pruebas de carrito.spec.ts
  await expect(page.getByText(/Ninguna prueba coincide/)).toBeHidden();
  await page.screenshot({ path: 'screenshots/insights.png', fullPage: true });
  expect(problems).toEqual([]);
});

test('tablero: filtro por rama y variación contra la ejecución anterior', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto(`/projects/${SLUG}`);
  await expect(page.locator('[data-delta="failed"]')).toHaveText(/vs anterior|= que la anterior/);
  await page.getByLabel('Rama').selectOption('main');
  await expect(page).toHaveURL(/rama=main/);
  await expect(page.locator('[data-latest-meta]')).toContainText('main');
  await page.getByText('Ver los datos de la gráfica en una tabla').click();
  const branches = await page.locator('[data-runs-body] tr td:nth-child(3)').allTextContents();
  expect(branches.length).toBeGreaterThan(0);
  expect(new Set(branches)).toEqual(new Set(['main'])); // solo ejecuciones de esa rama
  await page.locator('[data-compare-link]').click();
  await expect(page).toHaveURL(/compare\?base=\d+&head=\d+/);
  expect(problems).toEqual([]);
});

test('regenerar el token pide confirmación y lo cambia', async ({ page }) => {
  const problems = trackConsole(page);
  await page.goto('/');
  const name = `E2E token ${Date.now()}`;
  await page.getByLabel('Nombre').fill(name);
  await page.getByRole('button', { name: 'Crear proyecto' }).click();
  await page.getByRole('link', { name: `Ir al tablero de ${name} →` }).click();
  await page.getByText('Cómo subir un reporte a este proyecto').click();
  const before = await page.locator('code[id^="token-"]').textContent();

  page.once('dialog', (d) => d.dismiss()); // cancelar: no cambia
  await page.getByRole('button', { name: 'Regenerar token' }).click();
  await expect(page.locator('code[id^="token-"]')).toHaveText(before!);

  page.once('dialog', (d) => d.accept());
  await page.getByRole('button', { name: 'Regenerar token' }).click();
  await expect(page.getByText('Token regenerado')).toBeVisible();
  await expect(page.locator('code[id^="token-"]')).not.toHaveText(before!);
  expect(problems).toEqual([]);
});
