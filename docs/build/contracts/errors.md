# Errores de la API (RFC 9457, `application/problem+json`)

Forma: `{ "type": "https://qa-pulse.local/problems/<código>", "title", "status", "detail" }`.

| HTTP | `type` | Cuándo | Qué hacer |
|---|---|---|---|
| 401 | `invalid-token` | Falta `Authorization: Bearer`, token incorrecto, token de otro proyecto **o slug inexistente** (misma respuesta: no revela qué proyectos existen) | Copiar el token desde la página del proyecto |
| 404 | `not-found` | GET a `runs.json`/`flaky.json` de un slug inexistente (lecturas públicas) | Revisar el slug |
| 413 | `payload-too-large` | Cuerpo > 10 MB (se revisa antes de autenticar y de parsear) | Subir solo el reporte JSON, sin adjuntos |
| 422 | `invalid-report` | JSON inválido, sin `suites`, estructura inesperada, sin pruebas, anidamiento > 50 | Generar con `npx playwright test --reporter=json` |
| 422 | `invalid-params` | `branch` > 255 caracteres, `commit_sha` no hexadecimal (7–64) | Corregir el parámetro |

# Endpoints
- `POST /api/v1/projects/:slug/runs` — cuerpo crudo (cualquier Content-Type), `branch`/`commit_sha` en query o en el JSON de nivel superior. 201 → `Run#summary` + `url`.
- `GET /api/v1/projects/:slug/runs.json?limit=20` (1–100) → `{ project, runs: [summary…] }`, **orden cronológico ascendente** (lista para graficar).
- `GET /api/v1/projects/:slug/flaky.json?window=10` (1–100) → `{ window, rule, tests: [{ test_key, file, title, project_name, flaky_runs, flips, runs_seen, score, last_failure_message, last_failure_at, history_url }] }`.
- `summary` = `{ id, branch, commit_sha, started_at, duration_ms, total, passed, failed, skipped, flaky, pass_rate }`; `pass_rate` = (passed + flaky) / (total − skipped).
