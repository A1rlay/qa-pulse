import { test, expect } from '@playwright/test';
import { tienda } from './helpers';

test.describe('Checkout', () => {
  test.describe('Dirección', () => {
    test('valida el código postal', async ({ page }) => {
      await tienda(page, '<p role="alert">Código postal inválido</p>');
      await expect(page.getByRole('alert')).toBeVisible();
    });
    test('guarda una dirección nueva', async ({ page }) => {
      await tienda(page, '<p>Dirección guardada</p>');
      await expect(page.getByText('Dirección guardada')).toBeVisible();
    });
  });
  test.describe('Pago', () => {
    test('paga con tarjeta', async ({ page }) => {
      await tienda(page, '<p id="pago">Pago aprobado</p>');
      await expect(page.locator('#pago')).toHaveText('Pago aprobado');
    });
    test('rechaza una tarjeta vencida', async ({ page }) => {
      await tienda(page, '<p role="alert">Tarjeta vencida</p>');
      await expect(page.getByRole('alert')).toHaveText('Tarjeta vencida');
    });
    test('paga con PayPal', async ({ page }) => {
      test.skip(true, 'Sandbox de PayPal no disponible');
      await tienda(page, '<p>PayPal</p>');
    });
  });
  test('aplica un cupón de descuento', async ({ page }) => {
    // Regresión: el total no refleja el 10% de descuento.
    await tienda(page, '<p id="total">$298.00</p>');
    await expect(page.locator('#total')).toHaveText('$268.20', { timeout: 500 });
  });
  test('muestra la confirmación del pedido', async ({ page }) => {
    await tienda(page, '<h2>¡Gracias por tu compra!</h2>');
    await expect(page.getByRole('heading', { level: 2 })).toContainText('Gracias');
  });
  test('envía el correo de confirmación', async ({ page }) => {
    await tienda(page, '<p>Correo enviado</p>');
    await expect(page.getByText('Correo enviado')).toBeVisible();
  });
});
