// Página Insights: búsqueda de pruebas y métricas, todo por AJAX (fetch a la API JSON).
import "chart.umd"
import { el, formatDuration, formatDate, setState, getJSON } from "qa/dom"

const root = document.getElementById("insights")

if (root) {
  const { Chart } = window
  const $ = (selector) => root.querySelector(selector)
  const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  const runUrl = (id) => root.dataset.runUrlTemplate.replace("RUN_ID", encodeURIComponent(id))
  const branchSelect = document.getElementById("insights-branch")
  const STATUS = { passed: "Pasó", failed: "Falló", flaky: "Inestable", skipped: "Omitida" }
  let durationChart = null

  const withBranch = (url) => {
    const u = new URL(url, window.location.origin)
    if (branchSelect?.value) u.searchParams.set("branch", branchSelect.value)
    return u.toString()
  }

  // ---------- Búsqueda con debounce ----------
  const input = document.getElementById("test-search")
  const results = $("[data-search-results]")
  const searchState = $("[data-search-state]")
  let debounce = null
  let lastQuery = ""
  let searchController = null

  async function search(query) {
    searchController?.abort() // cancela la búsqueda anterior si aún no respondió
    searchController = new AbortController()
    const url = new URL(root.dataset.searchUrl, window.location.origin)
    url.searchParams.set("q", query)
    setState(searchState, "loading", "Buscando…")
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: searchController.signal })
      if (!response.ok) throw new Error(`el servidor respondió ${response.status}`)
      const { tests } = await response.json()
      if (query !== lastQuery) return
      if (tests.length === 0) {
        results.replaceChildren()
        setState(searchState, "empty", `Ninguna prueba coincide con «${query}».`)
        return
      }
      setState(searchState, "ok")
      results.replaceChildren(...tests.map((t) => el("li", {}, [
        el("a", { text: t.title, attrs: { href: t.history_url } }),
        el("span", { className: `badge badge--${t.last_status}`, text: STATUS[t.last_status] || t.last_status }),
        el("span", { className: "muted small", text: `${t.file} · ${t.project_name || "—"} · ${t.runs} ejecuciones` }),
      ])))
    } catch (error) {
      if (error.name === "AbortError") return
      setState(searchState, "error", `No se pudo buscar: ${error.message}.`)
    }
  }

  input.addEventListener("input", () => {
    clearTimeout(debounce)
    const query = input.value.trim()
    lastQuery = query
    if (query.length < 2) {
      results.replaceChildren()
      searchState.hidden = true
      return
    }
    debounce = setTimeout(() => search(query), 250)
  })
  $("[data-search-form]").addEventListener("submit", (event) => event.preventDefault())

  // ---------- Métricas ----------
  function drawDuration(runs) {
    const data = {
      labels: runs.map((r) => `#${r.id}`),
      datasets: [{ label: "Duración (s)", data: runs.map((r) => +(r.duration_ms / 1000).toFixed(1)),
                   borderColor: css("--chart-line"), backgroundColor: css("--chart-line"), tension: 0.25, pointRadius: 3 }],
    }
    if (durationChart) { durationChart.data = data; durationChart.update("none"); return }
    const text = css("--text-muted")
    durationChart = new Chart(document.getElementById("duration-chart"), {
      type: "line", data,
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: { legend: { display: false },
                   tooltip: { callbacks: { label: (ctx) => `${ctx.parsed.y} s` } } },
        scales: { y: { beginAtZero: true, ticks: { color: text, callback: (v) => `${v} s` }, grid: { color: css("--border") } },
                  x: { ticks: { color: text }, grid: { display: false } } },
      },
    })
  }

  function drawSlowest(tests, historyUrl) {
    const list = $("[data-slow-list]")
    const max = Math.max(...tests.map((t) => t.avg_ms), 1)
    list.replaceChildren(...tests.map((t) => el("li", {}, [
      el("div", { className: "slow-list__row" }, [
        el("a", { text: t.title, attrs: { href: historyUrl(t.test_key) } }),
        el("strong", { className: "num", text: formatDuration(t.avg_ms) }),
      ]),
      el("meter", { className: "bar", attrs: { min: "0", max: String(max), value: String(t.avg_ms) }, text: `${t.avg_ms} ms` }),
      el("span", { className: "muted small", text: `${t.file} · máx. ${formatDuration(t.max_ms)} · ${t.runs} ejecuciones` }),
    ])))
  }

  function drawHeatmap({ runs, tests }, historyUrl) {
    $("[data-heat-head]").replaceChildren(el("tr", {}, [
      el("th", { text: "Prueba", attrs: { scope: "col" } }),
      ...runs.map((r) => el("th", { attrs: { scope: "col", title: `${formatDate(r.started_at)} · ${r.branch || "sin rama"}` } }, [
        el("a", { text: `${r.id}`, attrs: { href: runUrl(r.id), "aria-label": `Ejecución ${r.id}` } }),
      ])),
    ]))
    $("[data-heat-body]").replaceChildren(...tests.map((t) => el("tr", {}, [
      el("th", { attrs: { scope: "row" } }, [el("a", { text: t.title, attrs: { href: historyUrl(t.test_key) } })]),
      ...t.statuses.map((status, i) => {
        const label = `#${runs[i].id}: ${status ? STATUS[status] : "no existía"}`
        return el("td", { className: `heatmap__cell heatmap__cell--${status || "none"}`, attrs: { title: label } },
                  [el("span", { className: "visually-hidden", text: label })])
      }),
    ])))
  }

  async function loadInsights() {
    const states = ["[data-duration-state]", "[data-slow-state]", "[data-heat-state]"].map($)
    states.forEach((s) => setState(s, "loading", "Cargando…"))
    try {
      const data = await getJSON(withBranch(root.dataset.insightsUrl))
      const historyUrl = (key) => data.history_url_template.replace("TEST_KEY", key)
      const [durState, slowState, heatState] = states

      if (data.heatmap.runs.length === 0) {
        states.forEach((s) => setState(s, "empty", "No hay ejecuciones para esta rama todavía."))
        ;["[data-duration-box]", "[data-slow-list]", "[data-heat-box]"].forEach((s) => { $(s).hidden = true })
        return
      }
      setState(durState, "ok"); $("[data-duration-box]").hidden = false
      drawDuration(data.heatmap.runs)

      if (data.slowest.length === 0) { setState(slowState, "empty", "Sin datos de duración."); $("[data-slow-list]").hidden = true }
      else { setState(slowState, "ok"); $("[data-slow-list]").hidden = false; drawSlowest(data.slowest, historyUrl) }

      if (data.heatmap.tests.length === 0) {
        setState(heatState, "empty", "Ninguna prueba falló en estas ejecuciones. 🎉"); $("[data-heat-box]").hidden = true
      } else { setState(heatState, "ok"); $("[data-heat-box]").hidden = false; drawHeatmap(data.heatmap, historyUrl) }
    } catch (error) {
      states.forEach((s) => setState(s, "error", `No se pudieron cargar las métricas: ${error.message}.`))
    }
  }

  if (branchSelect) {
    const initial = new URL(window.location).searchParams.get("rama")
    if (initial) branchSelect.value = initial
    branchSelect.addEventListener("change", () => {
      const url = new URL(window.location)
      if (branchSelect.value) url.searchParams.set("rama", branchSelect.value)
      else url.searchParams.delete("rama")
      history.replaceState(null, "", url)
      loadInsights()
    })
  }

  loadInsights()
}
