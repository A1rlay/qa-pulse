// Tablero del proyecto: carga por AJAX (fetch) runs.json y flaky.json, dibuja la gráfica con
// Chart.js y se refresca cada 10 s, así una subida nueva aparece sin recargar la página.
import "chart.umd" // define window.Chart
import { el, formatDuration, formatDate, setState, getJSON } from "qa/dom"

const root = document.getElementById("dashboard")

if (root) {
  const { Chart } = window

  const refreshMs = Number(root.dataset.refreshMs) || 10000
  const runUrl = (id) => root.dataset.runUrlTemplate.replace("RUN_ID", encodeURIComponent(id))
  const $ = (selector) => root.querySelector(selector)
  const live = document.getElementById("live-status")
  const liveText = live.querySelector("[data-live-text]")

  let chart = null
  let lastRunId = null
  let timer = null
  let inFlight = false
  let rerun = false // se pidió refrescar (p. ej. cambio de rama) mientras había una petición en curso

  const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  const branchSelect = document.getElementById("branch-filter")

  // Agrega ?branch= a las URLs de la API cuando hay una rama elegida.
  const withBranch = (url) => {
    const u = new URL(url, window.location.origin)
    if (branchSelect?.value) u.searchParams.set("branch", branchSelect.value)
    return u.toString()
  }

  // ---------- Ejecuciones: tarjetas, gráfica y tabla ----------
  // Cambio respecto a la ejecución anterior. good = "subir es bueno" (true), "subir es malo" (false) o neutro (null).
  const DELTAS = {
    total: { good: null }, passed: { good: true }, failed: { good: false }, flaky: { good: false },
    pass_rate: { good: true, unit: " pts" }, duration_ms: { good: false, format: formatDuration },
  }

  function updateCards(run, previous) {
    const values = {
      total: run.total, passed: run.passed, failed: run.failed, flaky: run.flaky,
      pass_rate: `${run.pass_rate}%`, duration_ms: formatDuration(run.duration_ms),
    }
    for (const [key, value] of Object.entries(values)) {
      const node = root.querySelector(`[data-stat="${key}"]`)
      if (node) node.textContent = value
      const deltaNode = root.querySelector(`[data-delta="${key}"]`)
      if (!deltaNode) continue
      deltaNode.classList.remove("is-good", "is-bad")
      if (!previous) { deltaNode.textContent = ""; continue }
      const diff = +(run[key] - previous[key]).toFixed(1)
      const { good, unit = "", format } = DELTAS[key]
      if (diff === 0) { deltaNode.textContent = "= que la anterior"; continue }
      const amount = format ? format(Math.abs(diff)) : `${Math.abs(diff)}${unit}`
      deltaNode.textContent = `${diff > 0 ? "▲" : "▼"} ${amount} vs anterior`
      if (good !== null) deltaNode.classList.add((diff > 0) === good ? "is-good" : "is-bad")
    }
    const meta = $("[data-latest-meta]")
    const parts = [
      el("a", { text: `#${run.id}`, attrs: { href: runUrl(run.id) } }),
      ` · ${formatDate(run.started_at)} · ${run.branch || "sin rama"}`,
    ]
    if (previous) {
      const compare = new URL(root.dataset.compareUrl, window.location.origin)
      compare.searchParams.set("base", previous.id)
      compare.searchParams.set("head", run.id)
      parts.push(" · ", el("a", { text: "¿qué cambió?", attrs: { href: compare.pathname + compare.search, "data-compare-link": "" } }))
    }
    meta.replaceChildren(...parts)
  }

  function updateTable(runs) {
    const rows = [...runs].reverse().map((run) =>
      el("tr", {}, [
        el("td", {}, [el("a", { text: `#${run.id}`, attrs: { href: runUrl(run.id) } })]),
        el("td", { text: formatDate(run.started_at) }),
        el("td", { text: run.branch || "—" }),
        el("td", { text: `${run.pass_rate}%` }),
        el("td", { text: run.failed }),
        el("td", { text: run.flaky }),
        el("td", { text: formatDuration(run.duration_ms) }),
      ])
    )
    $("[data-runs-body]").replaceChildren(...rows)
  }

  function drawChart(runs) {
    const data = {
      labels: runs.map((r) => `#${r.id}`),
      datasets: [
        { type: "line", label: "% de éxito", data: runs.map((r) => r.pass_rate), yAxisID: "pct",
          borderColor: css("--chart-line"), backgroundColor: css("--chart-line"), tension: 0.25, pointRadius: 3, order: 0 },
        { type: "bar", label: "Fallidas", data: runs.map((r) => r.failed), yAxisID: "count",
          backgroundColor: css("--failed"), stack: "tests", order: 1 },
        { type: "bar", label: "Inestables", data: runs.map((r) => r.flaky), yAxisID: "count",
          backgroundColor: css("--flaky"), stack: "tests", order: 1 },
      ],
    }

    if (chart) {
      chart.data = data
      chart.$runs = runs
      chart.update("none")
      return
    }

    const text = css("--text-muted")
    const grid = css("--border")
    chart = new Chart(document.getElementById("trend-chart"), {
      data,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: "index", intersect: false },
        scales: {
          pct: { position: "left", min: 0, max: 100, ticks: { color: text, callback: (v) => `${v}%` },
                 grid: { color: grid }, title: { display: true, text: "% de éxito", color: text } },
          count: { position: "right", beginAtZero: true, stacked: true, ticks: { color: text, precision: 0 },
                   grid: { display: false }, title: { display: true, text: "pruebas", color: text } },
          x: { stacked: true, ticks: { color: text }, grid: { display: false } },
        },
        plugins: {
          legend: { labels: { color: text } },
          tooltip: {
            callbacks: {
              title: (items) => {
                const run = chart.$runs[items[0].dataIndex]
                return `Ejecución #${run.id} · ${formatDate(run.started_at)} · ${run.branch || "sin rama"}`
              },
            },
          },
        },
        // Clic en una ejecución: abre su detalle.
        onClick: (_event, elements) => {
          if (elements.length) window.location.href = runUrl(chart.$runs[elements[0].index].id)
        },
      },
    })
    chart.$runs = runs
  }

  async function loadRuns() {
    const state = $("[data-chart-state]")
    try {
      const { runs } = await getJSON(withBranch(root.dataset.runsUrl))
      if (runs.length === 0) {
        $("[data-chart-box]").hidden = true
        $("[data-runs-body]").replaceChildren()
        setState(state, "empty", branchSelect?.value ? `No hay ejecuciones en la rama «${branchSelect.value}».` : "Todavía no hay ejecuciones. Sube un reporte con el comando de abajo y aparecerá aquí en menos de 10 segundos.")
        return
      }
      setState(state, "ok")
      $("[data-chart-box]").hidden = false
      drawChart(runs)
      updateTable(runs)
      const latest = runs[runs.length - 1]
      updateCards(latest, runs[runs.length - 2])
      if (lastRunId !== null && latest.id !== lastRunId) announceNewRun(latest)
      lastRunId = latest.id
    } catch (error) {
      // Si ya había datos se conservan (estado degradado) y se avisa del error.
      setState(state, "error", `No se pudieron cargar las ejecuciones: ${error.message}. ${chart ? "Mostrando los últimos datos recibidos." : ""} Se reintentará automáticamente.`)
      throw error
    }
  }

  function announceNewRun(run) {
    const cards = root.querySelector(".cards")
    cards.classList.remove("cards--flash")
    void cards.offsetWidth // reinicia la animación
    cards.classList.add("cards--flash")
    liveText.textContent = `Nueva ejecución #${run.id} recibida`
  }

  // ---------- Pruebas inestables ----------
  async function loadFlaky() {
    const state = $("[data-flaky-state]")
    const box = $("[data-flaky-box]")
    try {
      const { tests } = await getJSON(withBranch(root.dataset.flakyUrl))
      if (tests.length === 0) {
        box.hidden = true
        setState(state, "empty", "Ninguna prueba es inestable en las últimas ejecuciones. 🎉")
        return
      }
      setState(state, "ok")
      box.hidden = false
      $("[data-flaky-body]").replaceChildren(...tests.map(flakyRow))
    } catch (error) {
      setState(state, "error", `No se pudo cargar la lista de pruebas inestables: ${error.message}. Se reintentará automáticamente.`)
      throw error
    }
  }

  function flakyRow(test) {
    const errorCell = test.last_failure_message
      ? el("details", { className: "error-details" }, [
          el("summary", { text: test.last_failure_at ? `Falló el ${formatDate(test.last_failure_at)}` : "Ver error" }),
          el("pre", { className: "error", text: test.last_failure_message }),
        ])
      : el("span", { className: "muted", text: "—" })
    return el("tr", {}, [
      el("td", {}, [
        el("a", { text: test.title, attrs: { href: test.history_url, title: "Ver historial" } }),
        el("div", { className: "muted small", text: test.file }),
      ]),
      el("td", { text: test.project_name || "—" }),
      el("td", { className: "num", text: test.flaky_runs }),
      el("td", { className: "num", text: test.flips }),
      el("td", {}, [errorCell]),
    ])
  }

  // ---------- Ciclo de refresco ----------
  async function refresh() {
    if (inFlight) { rerun = true; return }
    inFlight = true
    rerun = false
    clearTimeout(timer)
    const results = await Promise.allSettled([loadRuns(), loadFlaky()])
    inFlight = false
    const ok = results.every((r) => r.status === "fulfilled")
    live.classList.toggle("live--error", !ok)
    if (!liveText.textContent.startsWith("Nueva ejecución") || !ok) {
      liveText.textContent = ok
        ? `En vivo · actualizado ${new Date().toLocaleTimeString("es-MX")}`
        : "Sin conexión · reintentando cada 10 s"
    } else {
      setTimeout(() => { liveText.textContent = `En vivo · actualizado ${new Date().toLocaleTimeString("es-MX")}` }, 4000)
    }
    if (rerun) return refresh()
    if (!document.hidden) timer = setTimeout(refresh, refreshMs)
  }

  // Pestaña oculta: se pausa el sondeo; al volver se actualiza de inmediato.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) clearTimeout(timer)
    else refresh()
  })

  if (branchSelect) {
    const initial = new URL(window.location).searchParams.get("rama")
    if (initial && [...branchSelect.options].some((o) => o.value === initial)) branchSelect.value = initial
    branchSelect.addEventListener("change", () => {
      const url = new URL(window.location)
      if (branchSelect.value) url.searchParams.set("rama", branchSelect.value)
      else url.searchParams.delete("rama")
      history.replaceState(null, "", url) // la rama elegida queda en la URL
      lastRunId = null // cambiar de rama no es "una ejecución nueva"
      refresh()
    })
  }

  refresh()
}
