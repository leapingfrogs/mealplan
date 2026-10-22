// Drag-and-drop reordering for a list whose rows carry data-id. The list
// needs data-sortable="true" (anything else turns dragging off) and
// data-event, the event pushed with the new order as {ids: [...]}.
// Phones reorder with the rows' up/down buttons instead.
export default {
  mounted() {
    let dragged = null
    const rows = () => [...this.el.querySelectorAll("li[data-id]")]

    this.el.addEventListener("dragstart", e => {
      if (this.el.dataset.sortable !== "true") return
      dragged = e.target.closest("li[data-id]")
      if (!dragged) return
      e.dataTransfer.effectAllowed = "move"
      dragged.classList.add("opacity-50")
    })
    this.el.addEventListener("dragover", e => {
      if (!dragged) return
      e.preventDefault()
      const over = e.target.closest("li[data-id]")
      if (!over || over === dragged) return
      const box = over.getBoundingClientRect()
      const after = e.clientY > box.top + box.height / 2
      this.el.insertBefore(dragged, after ? over.nextSibling : over)
    })
    this.el.addEventListener("drop", e => e.preventDefault())
    this.el.addEventListener("dragend", () => {
      if (!dragged) return
      dragged.classList.remove("opacity-50")
      dragged = null
      this.pushEvent(this.el.dataset.event, {ids: rows().map(li => li.dataset.id)})
    })
  }
}
