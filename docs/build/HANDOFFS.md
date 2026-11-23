# Handoffs

### dbms + backend — Paso 1 (scaffold, modelos, seeds) — 2026-11-22
**Did:** App Rails 8.1.4 + MySQL; 3 tablas con CHECKs; modelos; `FlakyDetector`; suite Playwright real de 30 pruebas
(`spec/fixtures/playwright_suite`) y su reporte JSON; seeds de 15 ejecuciones; 17 specs.
**Decisions:** ver `adr/0001-stack-and-shape.md` y `data/schema.md` (hash como identidad en vez de índice por prefijo;
índice no único en vez de único).
**Provides:** `Run#recompute_counts!`, `Run#summary`, `TestResult.key_for`, `FlakyDetector#call`.
**Risks:** (bajo) Arch/MySQL 8.4 vs XAMPP/MariaDB: CHECK se aplica en MariaDB ≥10.2; probar `db:setup` en la máquina XAMPP antes del martes.
**Named but not implemented:** límite de 10 MB, `secure_compare` en la API, limpieza de ANSI → Paso 2.
**Next:** backend — parser + API; debe responder: ¿un test `unexpected` con `expectedStatus: failed` cuenta como failed?

### backend + red-team — Paso 2 (parser + API) — 2026-11-22
**Did:** `PlaywrightReportParser`, `RunIngestor` (transacción, `insert_all` por lotes, totales recalculados), API v1
(POST runs, GET runs.json, GET flaky.json), middleware `RawReportBody`, `bin/demo_upload`, 63 specs.
**Decisions:**
- Mapeo de estados: `expected`→passed (incluye `test.fail()` cumplido), `unexpected`→failed, `skipped`→skipped;
  flaky si `status: flaky` **o** el último intento pasó tras uno failed/timedOut/interrupted. Rechazado: confiar solo en `status`. Costo: ninguno visible.
- El cuerpo nunca pasa por `params` (middleware lo marca `application/octet-stream`). Rechazado: `filter_parameters` +
  `rescue_from` — no cubre el parseo que hace la instrumentación de Rails antes de los callbacks. Costo: el upload no
  puede leer parámetros de formulario (solo query string y JSON).
- Slug inexistente en POST → 401, no 404. Costo: mensaje menos específico para quien se equivoca de slug.
- Lecturas (`runs.json`, `flaky.json`) públicas: no hay usuarios en la app (etapa 0). Revisar si se despliega fuera de localhost.
**Break gate (servidor real + curl), probado:** 3 defectos encontrados y corregidos con spec de regresión —
(A) el log volcaba el reporte completo; (B) sin token + JSON roto daba 422 en vez de 401; (C) `curl -d` (form-urlencoded)
daba 500 por `Rack::MethodOverride`. Más: `limit=abc` devolvía 1; `bearer` en minúsculas se rechazaba;
`db:seed` no era re-ejecutable (`has_many#delete_all` anula la FK) aunque el comentario decía que sí.
**Held up:** token de otro proyecto → 401; 11 MB con y sin Content-Length → 413 sin parsear; `_method=DELETE` ignorado;
transacción sin ejecución a medias; conteos de `stats` manipulados ignorados; `branch` como objeto descartado.
**Mutaciones:** 7 mutaciones (token, recálculo, transacción, flaky, 10 MB, título, ANSI) → todas detectadas.
**Named but not implemented:**
- `branch` con HTML se guarda tal cual (correcto) → el Paso 3 **debe** pintarlo con `textContent`/ERB, nunca `innerHTML`.
- Un 413 por chunked lee hasta el final del cuerpo antes de rechazar (Puma ya lo bufferea). Aceptado en etapa 0.
- Rutas `/api/...` que no existen devuelven la página 404 HTML, no problem+json. Diferido: cosmético.
**Next:** frontend — Paso 3; debe responder: ¿qué muestra el dashboard mientras runs.json carga, si falla y si no hay ejecuciones?

### frontend + tester — Pasos 3 y 4 (páginas, AJAX, README) — 2026-11-22
**Did:** 4 páginas server-rendered en español; `dashboard.js` (fetch cada 10 s, pausa con pestaña oculta,
estados cargando/vacío/error/éxito, error conserva los datos previos); filtro por estado en el cliente con el filtro
en la URL; CSP estricta con nonce; Chart.js descargado; `bin/e2e` (Playwright en Docker, 5 recorridos, limpia lo que crea);
README en español con Mermaid (verificado renderizando con mermaid-cli); 78 specs + 5 E2E; Brakeman 0 avisos; RuboCop limpio.
**Decisions:**
- Sin Turbo/Stimulus: módulos vanilla por página. Rechazado: Hotwire. Costo: más JS a mano.
- Barras de duración con `<meter>` en vez de `style="width:…"`: la CSP bloquea estilos en línea.
- Tabla alternativa de los datos de la gráfica (accesibilidad: el canvas no es legible por lectores de pantalla).
**Break gate, probado:** E2E encontró que el build jspm de Chart.js pedía `/_/6Mg_Thua.js` (404) → reemplazado.
Las capturas revelaron un comentario ERB que imprimía `(escapado). %>` → corregido + spec que busca `%>` en las páginas.
Una prueba E2E de XSS por AJAX falla con un mutante que usa `innerHTML` (verificado) y pasa con `textContent`.
**Named but not implemented:**
- Lecturas públicas y sin usuarios (ADR 0001): aceptado para etapa 0 / localhost.
- La regla flaky se calcula en Ruby sobre las últimas 10 ejecuciones en cada petición (≈300 filas): sin caché. Revisar si una ejecución supera ~5k pruebas.
- Probar en XAMPP/MariaDB y en Windows antes del martes (CHECK constraints, compilación de mysql2, scripts bash → Git Bash).
**Next:** product — después de la presentación: ¿se necesita filtrar el tablero por rama?

### product + backend + frontend — Mejoras (rama `mejoras`) — 2026-11-22
**Did:** comparar ejecuciones (`RunComparison`), Insights (`ProjectInsights`: lentas, mapa de calor; `TestSearch`:
búsqueda AJAX), filtro por rama (tablero, Insights, API), variación vs anterior en las tarjetas, mini gráficas
(SVG del servidor) en Proyectos, insignia SVG, CSV, regenerar token, workflow de GitHub Actions. 110 specs + 9 E2E.
**Decisions:**
- Sin cuentas de usuario. Rechazado: login con has_secure_password. Costo: lecturas públicas (ver ADR 0001).
  Motivo: tocaba todas las páginas a 2 días de la presentación y complicaba la demo.
- Una prueba nueva que falla cuenta como "nueva falla" y no como "agregada". Rechazado: categorías disjuntas por
  existencia. Costo: "Pruebas nuevas" solo lista las que no fallan.
- "Más lenta" = ≥ 50 % **y** ≥ 200 ms. Rechazado: solo relativo (ruido en pruebas de 10 ms).
- `allow_browser` solo para HTML: el proxy de imágenes de GitHub y curl no son navegadores modernos.
**Break gate, probado:** el spec encontró que una prueba nueva y rota se clasificaba como "agregada" (se ocultaba
una falla) → corregido. El paso de CI con `--get` + `--upload-file` sale con código 2 en curl → reescrito y
ejecutado tal cual contra el servidor (rama con espacio y `&`). La mutación sin `sanitize_sql_like` hace fallar un spec.
**Held up:** insignia con nombre `<script>` escapada; celda `=HYPERLINK(...)` neutralizada; regenerar token sin CSRF → 422;
por GET → 404; ejecución de otro proyecto en Comparar → 404.
**Named but not implemented:** Insights recalcula en cada petición (sin caché); aceptable con ≤ 100 ejecuciones × 30 pruebas.
