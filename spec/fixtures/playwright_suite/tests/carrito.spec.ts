import { test, expect } from '@playwright/test';
import { tienda } from './helpers';

test.describe('Carrito', () => {
  test('agrega un producto', async ({ page }) => {
    await tienda(page, '<ul id="carrito"><li>Taza</li></ul>');
    await expect(page.locator('#carrito li')).toHaveCount(1);
  });
  test('elimina un producto', async ({ page }) => {
    await tienda(page, '<ul id="carrito"></ul><p>Carrito vacío</p>');
    await expect(page.getByText('Carrito vacío')).toBeVisible();
  });
  test('cambia la cantidad', async ({ page }) => {
    await tienda(page, '<input id="cantidad" value="3">');
    await expect(page.locator('#cantidad')).toHaveValue('3');
  });
  test('calcula el subtotal', async ({ page }) => {
    await tienda(page, '<p id="subtotal">$298.00</p>');
    await expect(page.locator('#subtotal')).toHaveText('$298.00');
  });
  test('actualiza el contador del ícono', async ({ page }, testInfo) => {
    // Inestable a propósito.
    await tienda(page, `<span id="badge">${testInfo.retry === 0 ? '0' : '2'}</span>`);
    await expect(page.locator('#badge')).toHaveText('2', { timeout: 500 });
  });
  test('conserva el carrito al recargar', async ({ page }) => {
    await tienda(page, '<ul id="carrito"><li>Gorra</li></ul>');
    await expect(page.locator('#carrito li')).toHaveText('Gorra');
  });
  test('limita la cantidad al stock', async ({ page }) => {
    await tienda(page, '<p role="alert">Solo quedan 2 piezas</p>');
    await expect(page.getByRole('alert')).toContainText('2 piezas');
  });
  test('aplica envío gratis desde $999', async ({ page }) => {
    await tienda(page, '<p id="envio">Envío gratis</p>');
    await expect(page.locator('#envio')).toHaveText('Envío gratis');
  });
});
