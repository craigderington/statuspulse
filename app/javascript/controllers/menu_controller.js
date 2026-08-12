import { Controller } from "@hotwired/stimulus"

// A small dropdown for account actions.
//
// Deliberately closes on outside click and on Escape, and returns focus to the
// trigger — a menu you can open but not dismiss with the keyboard is worse than
// no menu.
export default class extends Controller {
  static targets = ["trigger", "menu"]

  connect() {
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.onKeydown = (event) => {
      if (event.key === "Escape" && this.isOpen) {
        this.close()
        this.triggerTarget.focus()
      }
    }

    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  get isOpen() {
    return this.menuTarget.dataset.open === "true"
  }

  toggle(event) {
    event.preventDefault()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.menuTarget.dataset.open = "true"
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.menuTarget.querySelector("a, button")?.focus()
  }

  close() {
    this.menuTarget.dataset.open = "false"
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }
}
