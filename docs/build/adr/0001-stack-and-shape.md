# ADR 0001 — Stack y forma de la app

**Estado:** aceptado · **Etapa:** 0 (demo académica, 1 usuario) · **Revisar si:** >1 proyecto con >10k resultados por ejecución.

| Decisión | Alternativa rechazada | Costo aceptado |
|---|---|---|
| Monolito Rails 8.1, vistas server-rendered + `fetch` vanilla | Hotwire/Turbo (`--skip-hotwire`) | Más JS a mano; a cambio el AJAX es explícito y visible para la evaluación |
| MySQL (XAMPP), `database.yml` lee `DB_USER/DB_PASSWORD/DB_HOST/DB_PORT` | SQLite (default de Rails 8) | Requiere servidor MySQL; en esta máquina se usa `mysql:8.4` en Docker con las mismas credenciales que XAMPP |
| CSS plano | Tailwind | Menos utilidades; cero build step y una dependencia menos |
| Chart.js 4.4.1 UMD descargado en `vendor/javascript` (sha1 verificado contra npm) | CDN; build ESM de jspm (importa un chunk `/_/…` que la app no sirve: falló en E2E) | Actualizar Chart.js es manual; a cambio la demo funciona sin internet y la CSP no permite orígenes externos |
| Gems en `vendor/bundle` | Gems de usuario (`GEM_HOME`) | Carpeta más pesada; `bin/rails` funciona sin configurar el shell |
| `api_token` guardado en claro (64 hex, único) | Guardar solo un digest | Un volcado de la BD expone tokens; el enunciado exige mostrar el token y el `curl` en la UI. Comparación con `secure_compare` |
| Sin cola de jobs: ingesta síncrona en una transacción | ActiveJob/Solid Queue | Una subida grande bloquea un hilo de Puma; se limita a 10 MB |
