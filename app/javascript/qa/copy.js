// Botones "Copiar": copian el texto del elemento indicado en data-copy-target.
document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-target]")
  if (!button) return
  const source = document.getElementById(button.dataset.copyTarget)
  if (!source) return
  const original = button.textContent
  try {
    await navigator.clipboard.writeText(source.textContent)
    button.textContent = "¡Copiado!"
  } catch {
    // Sin permiso de portapapeles: se selecciona el texto para copiarlo con Ctrl+C.
    const range = document.createRange()
    range.selectNodeContents(source)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
    button.textContent = "Selecciona y Ctrl+C"
  }
  setTimeout(() => { button.textContent = original }, 1800)
})
