import { Page } from '@playwright/test';
// Páginas mínimas en memoria: la suite no depende de ningún servidor.
export async function tienda(page: Page, body: string) {
  await page.setContent(`<main><h1>Tienda Demo</h1>${body}</main>`);
}
