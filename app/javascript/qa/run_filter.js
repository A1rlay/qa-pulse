// Detalle de ejecución: filtra las filas por estado sin recargar (todo en el cliente).
const root = document.getElementById("run-results")

if (root) {
  const buttons = [...root.querySelectorAll("[data-filter]")]
  const rows = [...root.querySelectorAll("tbody tr[data-status]")]
  const status = root.querySelector("[data-filter-status]")
  const empty = root.querySelector("[data-filter-empty]")

  const apply = (filter) => {
    let visible = 0
    for (const row of rows) {
      const show = filter === "all" || row.dataset.status === filter
      row.hidden = !show
      if (show) visible++
    }
    for (const button of buttons) button.setAttribute("aria-pressed", String(button.dataset.filter === filter))
    status.textContent = `Mostrando ${visible} de ${rows.length} pruebas.`
    empty.hidden = visible > 0
    const url = new URL(window.location)
    if (filter === "all") url.searchParams.delete("estado")
    else url.searchParams.set("estado", filter)
    history.replaceState(null, "", url) // el filtro queda en la URL (se puede compartir)
  }

  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-filter]")
    if (button && !button.disabled) apply(button.dataset.filter)
  })

  const initial = new URL(window.location).searchParams.get("estado")
  if (initial && buttons.some((b) => b.dataset.filter === initial)) apply(initial)
}
