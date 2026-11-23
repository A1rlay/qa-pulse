import { test, expect } from '@playwright/test';
import { tienda } from './helpers';

test.describe('Autenticación', () => {
  test('inicia sesión con credenciales válidas', async ({ page }) => {
    await tienda(page, '<p id="saludo">Hola, Ana</p>');
    await expect(page.locator('#saludo')).toHaveText('Hola, Ana');
  });
  test('rechaza contraseña incorrecta', async ({ page }) => {
    await tienda(page, '<p role="alert">Credenciales inválidas</p>');
    await expect(page.getByRole('alert')).toContainText('inválidas');
  });
  test('bloquea la cuenta tras 5 intentos', async ({ page }) => {
    await tienda(page, '<p role="alert">Cuenta bloqueada</p>');
    await expect(page.getByRole('alert')).toHaveText('Cuenta bloqueada');
  });
  test('cierra sesión por inactividad', async ({ page }, testInfo) => {
    // Inestable a propósito: falla en el primer intento y pasa al reintentar.
    await tienda(page, `<p id="estado">${testInfo.retry === 0 ? 'Sesión activa' : 'Sesión expirada'}</p>`);
    await expect(page.locator('#estado')).toHaveText('Sesión expirada', { timeout: 500 });
  });
  test.describe('Recuperar contraseña', () => {
    test('envía el correo de recuperación', async ({ page }) => {
      await tienda(page, '<p>Te enviamos un correo</p>');
      await expect(page.getByText('Te enviamos un correo')).toBeVisible();
    });
    test('rechaza un enlace caducado', async ({ page }) => {
      await tienda(page, '<p role="alert">Enlace caducado</p>');
      await expect(page.getByRole('alert')).toBeVisible();
    });
  });
});
