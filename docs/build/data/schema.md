# Esquema (MySQL 8 / MariaDB 10.4+)

- `projects` — `slug` único (URL), `api_token` único (64 hex).
- `runs` — FK `project_id` indexada vía `(project_id, started_at)`: cubre "últimas N ejecuciones".
  CHECK `runs_non_negative` y `runs_total_matches` (`total = passed+failed+skipped+flaky`):
  los totales los recalcula el servidor (`Run#recompute_counts!`) y la BD rechaza cualquier camino que los descuadre.
- `test_results` — FK `run_id` indexada vía `(run_id, status)` (también sirve al filtro de la vista de ejecución).
  `test_key` = SHA-256(file ␀ title ␀ project_name), índice `(test_key, run_id)` para el historial por prueba.
  - Por qué un hash: `title` es TEXT (no indexable completo) y la colación `utf8mb4_unicode_ci` ignora mayúsculas/acentos;
    el hash es de ancho fijo y distingue "Agrega" de "agrega".
  - **No es único**: `--repeat-each` o títulos duplicados producen varias filas por prueba en una ejecución.
  - CHECK `status IN (passed, failed, skipped, flaky)` y no-negativos.
- Tiempos: `DATETIME(6)` en UTC (Rails). MySQL no tiene TIMESTAMPTZ; la conversión de zona es de la app.
- FKs con RESTRICT (default). No hay borrado en la UI; `Project` usa `restrict_with_error`.

## Mapeo del reporte de Playwright (verificado contra spec/fixtures/playwright_report.json, v1.59.0)
`suites[]` (una por archivo; `title` = nombre de archivo) → `suites[]` anidadas (describe) → `specs[]` (`title`, `file`)
→ `tests[]` (`projectName`, `status`: expected|unexpected|flaky|skipped, `expectedStatus`) → `results[]`
(`status`, `retry`, `duration`, `error.message`, `errors[]`). Los mensajes traen códigos ANSI: hay que limpiarlos.
`stats` = `{startTime, duration, expected, unexpected, flaky, skipped}`.
