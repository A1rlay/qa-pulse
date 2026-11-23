# Datos de demostración: proyecto "Tienda Demo" con 15 ejecuciones históricas de 30 pruebas.
# Las identidades (archivo + título) coinciden con spec/fixtures/playwright_report.json,
# así que una subida en vivo con bin/demo_upload continúa este mismo historial.
#
# Guion de la historia:
#   - 3 pruebas inestables (flaky): fallan y pasan sin cambios de código.
#   - 1 regresión real: "Checkout > aplica un cupón de descuento" pasa en las ejecuciones 1-12
#     y falla siempre en las 3 más recientes (un solo cambio de estado: NO es inestable).
#   - "Checkout > Pago > paga con PayPal" siempre se omite (skipped).
# Se puede volver a ejecutar: reemplaza las ejecuciones del proyecto.

TESTS = [
  [ "auth.spec.ts", "Autenticación > inicia sesión con credenciales válidas" ],
  [ "auth.spec.ts", "Autenticación > rechaza contraseña incorrecta" ],
  [ "auth.spec.ts", "Autenticación > bloquea la cuenta tras 5 intentos" ],
  [ "auth.spec.ts", "Autenticación > cierra sesión por inactividad" ],
  [ "auth.spec.ts", "Autenticación > Recuperar contraseña > envía el correo de recuperación" ],
  [ "auth.spec.ts", "Autenticación > Recuperar contraseña > rechaza un enlace caducado" ],
  [ "carrito.spec.ts", "Carrito > agrega un producto" ],
  [ "carrito.spec.ts", "Carrito > elimina un producto" ],
  [ "carrito.spec.ts", "Carrito > cambia la cantidad" ],
  [ "carrito.spec.ts", "Carrito > calcula el subtotal" ],
  [ "carrito.spec.ts", "Carrito > actualiza el contador del ícono" ],
  [ "carrito.spec.ts", "Carrito > conserva el carrito al recargar" ],
  [ "carrito.spec.ts", "Carrito > limita la cantidad al stock" ],
  [ "carrito.spec.ts", "Carrito > aplica envío gratis desde $999" ],
  [ "catalogo.spec.ts", "Catálogo > muestra la lista de productos" ],
  [ "catalogo.spec.ts", "Catálogo > abre el detalle de un producto" ],
  [ "catalogo.spec.ts", "Catálogo > pagina los resultados" ],
  [ "catalogo.spec.ts", "Catálogo > Búsqueda > encuentra productos por nombre" ],
  [ "catalogo.spec.ts", "Catálogo > Búsqueda > muestra mensaje sin resultados" ],
  [ "catalogo.spec.ts", "Catálogo > Búsqueda > ignora mayúsculas y acentos" ],
  [ "catalogo.spec.ts", "Catálogo > Filtros > filtra por categoría" ],
  [ "catalogo.spec.ts", "Catálogo > Filtros > filtra por rango de precio" ],
  [ "checkout.spec.ts", "Checkout > aplica un cupón de descuento" ],
  [ "checkout.spec.ts", "Checkout > muestra la confirmación del pedido" ],
  [ "checkout.spec.ts", "Checkout > envía el correo de confirmación" ],
  [ "checkout.spec.ts", "Checkout > Dirección > valida el código postal" ],
  [ "checkout.spec.ts", "Checkout > Dirección > guarda una dirección nueva" ],
  [ "checkout.spec.ts", "Checkout > Pago > paga con tarjeta" ],
  [ "checkout.spec.ts", "Checkout > Pago > rechaza una tarjeta vencida" ],
  [ "checkout.spec.ts", "Checkout > Pago > paga con PayPal" ]
].freeze

RUNS = 15
rng = Random.new(2026)

# Patrón por ejecución (índice 0 = la más antigua). P = passed, F = failed, K = flaky.
PATTERNS = {
  "Autenticación > cierra sesión por inactividad" => "PPKPPKPPPKPPKPK",
  "Catálogo > Filtros > filtra por rango de precio" => "PFPPFPPFPPPFPFP",
  "Carrito > actualiza el contador del ícono" => "PPPKFPPKPPFPKPP",
  "Checkout > aplica un cupón de descuento" => "PPPPPPPPPPPPFFF"
}.freeze

ERRORS = {
  "Autenticación > cierra sesión por inactividad" =>
    "Error: expect(locator).toHaveText(expected) failed\n\nLocator:  locator('#estado')\n"     "Expected: \"Sesión expirada\"\nReceived: \"Sesión activa\"\nTimeout:  500ms",
  "Catálogo > Filtros > filtra por rango de precio" =>
    "Error: expect(locator).toHaveCount(expected) failed\n\nLocator:  getByRole('listitem')\n"     "Expected: 2\nReceived: 3\nTimeout:  500ms",
  "Carrito > actualiza el contador del ícono" =>
    "Error: expect(locator).toHaveText(expected) failed\n\nLocator:  locator('#badge')\n"     "Expected: \"2\"\nReceived: \"0\"\nTimeout:  500ms",
  "Checkout > aplica un cupón de descuento" =>
    "Error: expect(locator).toHaveText(expected) failed\n\nLocator:  locator('#total')\n"     "Expected: \"$268.20\"\nReceived: \"$298.00\"\nTimeout:  500ms"
}.freeze

ActiveRecord::Base.transaction do
  project = Project.find_or_create_by!(slug: "tienda-demo") do |p|
    p.name = "Tienda Demo"
    p.api_token = ENV["DEMO_API_TOKEN"].presence
  end
  TestResult.where(run_id: project.runs.select(:id)).delete_all
  Run.where(project_id: project.id).delete_all # no project.runs.delete_all: eso intenta anular project_id

  now = Time.current
  RUNS.times do |i|
    started_at = now - (RUNS - i).days + rng.rand(0..3600).seconds
    run = project.runs.create!(
      branch: i >= 12 ? "feature/cupones" : "main",
      commit_sha: format("%040x", rng.rand(16**40)),
      started_at: started_at
    )

    rows = TESTS.map do |file, title|
      code = PATTERNS.fetch(title, "P" * RUNS)[i]
      skipped = title.include?("PayPal")
      status = if skipped then "skipped"
      else { "P" => "passed", "F" => "failed", "K" => "flaky" }.fetch(code)
      end
      retries = { "passed" => 0, "skipped" => 0, "flaky" => 1, "failed" => 2 }.fetch(status)
      {
        run_id: run.id, file: file, title: title, project_name: "chromium",
        test_key: TestResult.key_for(file, title, "chromium"), status: status,
        duration_ms: skipped ? 0 : rng.rand(180..2400) * (retries + 1), retries: retries,
        error_message: %w[failed flaky].include?(status) ? ERRORS.fetch(title) : nil,
        created_at: now, updated_at: now
      }
    end
    TestResult.insert_all!(rows)
    run.recompute_counts!
    run.update!(duration_ms: rows.sum { |r| r[:duration_ms] } / 4) # 4 workers en paralelo
  end

  puts "Proyecto: #{project.name} (#{project.slug}) — #{project.runs.count} ejecuciones, "        "#{TestResult.where(run_id: project.runs.select(:id)).count} resultados"
  puts "API token: #{project.api_token}"
end
