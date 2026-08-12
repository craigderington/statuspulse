import { Controller } from "@hotwired/stimulus"

// Copies the recovery codes, and confirms it actually happened.
//
// A copy button that looks identical before and after leaves people unsure
// whether it worked — which, for codes shown exactly once, matters more than
// usual.
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = Array.from(this.sourceTarget.children)
      .map((node) => node.textContent.trim())
      .join("\n")

    navigator.clipboard.writeText(text).then(
      () => this.feedback("Copied"),
      () => this.feedback("Press Ctrl+C to copy")
    )
  }

  feedback(message) {
    const button = this.buttonTarget
    if (this.original === undefined) this.original = button.textContent

    button.textContent = message
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { button.textContent = this.original }, 2000)
  }
}
