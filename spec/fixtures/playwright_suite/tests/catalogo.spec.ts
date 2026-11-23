import { test, expect } from '@playwright/test';
import { tienda } from './helpers';

test.describe('Catálogo', () => {
  test('muestra la lista de productos', async ({ page }) => {
    await tienda(page, '<ul><li>Taza</li><li>Playera</li><li>Gorra</li></ul>');
    await expect(page.getByRole('listitem')).toHaveCount(3);
  });
  test('abre el detalle de un producto', async ({ page }) => {
    await tienda(page, '<h2>Taza QA</h2><p class="precio">$149.00</p>');
    await expect(page.locator('.precio')).toHaveText('$149.00');
  });
  test('pagina los resultados', async ({ page }) => {
    await tienda(page, '<nav><a>1</a><a>2</a><a>3</a></nav>');
    await expect(page.locator('nav a')).toHaveCount(3);
  });
  test.describe('Búsqueda', () => {
    test('encuentra productos por nombre', async ({ page }) => {
      await tienda(page, '<ul><li>Taza QA</li></ul>');
      await expect(page.getByText('Taza QA')).toBeVisible();
    });
    test('muestra mensaje sin resultados', async ({ page }) => {
      await tienda(page, '<p>Sin resultados para "xyz"</p>');
      await expect(page.getByText('Sin resultados')).toBeVisible();
    });
    test('ignora mayúsculas y acentos', async ({ page }) => {
      await tienda(page, '<ul><li>Café</li></ul>');
      await expect(page.getByText('Café')).toBeVisible();
    });
  });
  test.describe('Filtros', () => {
    test('filtra por categoría', async ({ page }) => {
      await tienda(page, '<ul><li>Playera</li></ul>');
      await expect(page.getByRole('listitem')).toHaveCount(1);
    });
    test('filtra por rango de precio', async ({ page }, testInfo) => {
      // Inestable a propósito.
      const n = testInfo.retry === 0 ? 3 : 2;
      await tienda(page, '<ul>' + '<li>Producto</li>'.repeat(n) + '</ul>');
      await expect(page.getByRole('listitem')).toHaveCount(2, { timeout: 500 });
    });
  });
});
