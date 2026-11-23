// Formularios con data-confirm: piden confirmación antes de enviarse (ej. regenerar el token).
document.addEventListener("submit", (event) => {
  const message = event.target.dataset?.confirm
  if (message && !window.confirm(message)) event.preventDefault()
})
