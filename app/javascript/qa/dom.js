// Utilidades de DOM. Regla de seguridad: los datos de los reportes (títulos, ramas, errores)
// se insertan SIEMPRE como texto (textContent), nunca como HTML (innerHTML).
export function el(tag, { className, text, attrs } = {}, children = []) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text !== undefined && text !== null) node.textContent = String(text)
  for (const [key, value] of Object.entries(attrs || {})) node.setAttribute(key, value)
  for (const child of children) if (child) node.append(child)
  return node
}

export function formatDuration(ms) {
  ms = Number(ms) || 0
  if (ms < 1000) return `${ms} ms`
  if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`
  return `${Math.floor(ms / 60000)} min ${Math.floor((ms % 60000) / 1000)} s`
}

const dateFormat = new Intl.DateTimeFormat("es-MX", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })
export const formatDate = (iso) => dateFormat.format(new Date(iso))

// Muestra un estado asíncrono: loading | empty | error | ok (ok oculta el mensaje).
export function setState(node, state, message) {
  node.dataset.state = state
  node.hidden = state === "ok"
  if (message) node.textContent = message
  node.setAttribute("role", state === "error" ? "alert" : "status")
}

// fetch JSON con tiempo límite; lanza Error con mensaje legible.
export async function getJSON(url, { timeoutMs = 8000 } = {}) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: controller.signal })
    if (!response.ok) throw new Error(`el servidor respondió ${response.status}`)
    return await response.json()
  } catch (error) {
    if (error.name === "AbortError") throw new Error("el servidor tardó demasiado")
    if (error instanceof TypeError) throw new Error("no hay conexión con el servidor")
    throw error
  } finally {
    clearTimeout(timer)
  }
}
